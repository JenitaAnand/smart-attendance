import os
import datetime
import numpy as np
import insightface
from fastapi import FastAPI, UploadFile, File, Form, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from sqlalchemy import and_
from database import engine, SessionLocal, Base
import models
from openpyxl import Workbook
import cv2
import shutil
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
import models

import albumentations as A
# ============== ENCODINGS ==============
import pickle
augment = A.Compose([
    A.HorizontalFlip(p=0.5),
    A.RandomBrightnessContrast(p=0.5),
    A.ShiftScaleRotate(shift_limit=0.02, scale_limit=0.05, rotate_limit=15, p=0.7)
])
# --- DB tables ---
Base.metadata.create_all(bind=engine)

# --- FastAPI app & CORS ---
app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- DB session dep ---
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Face model ---
model = insightface.app.FaceAnalysis(name="buffalo_l")
model.prepare(ctx_id=0, det_size=(640, 640))

# --- Storage ---
UPLOAD_DIR = "uploads"
STUDENT_IMG_DIR = "student_images"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(STUDENT_IMG_DIR, exist_ok=True)

# --- In-memory encodings per course: { course_id: {student_id: embedding(np.ndarray)} } ---
encodings_store: dict[int, dict[int, np.ndarray]] = {}


# ============== AUTH ==============
@app.post("/signup")
def signup(
    name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
):
    existing = db.query(models.Teacher).filter_by(email=email).first()
    if existing:
        return {"success": False, "msg": "Email already exists"}

    teacher = models.Teacher(name=name, email=email)
    teacher.set_password(password)   # 🔑 hash it here

    db.add(teacher)
    db.commit()
    db.refresh(teacher)
    return {
        "success": True,
        "teacher": {"id": teacher.id, "name": teacher.name, "email": teacher.email},
    }



@app.post("/login")
def login(
    email: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
):
    teacher = db.query(models.Teacher).filter_by(email=email).first()
    if not teacher:
        return {"success": False, "msg": "Not registered"}

    if not teacher.verify_password(password):
        return {"success": False, "msg": "Invalid password"}

    return {
        "success": True,
        "teacher": {"id": teacher.id, "name": teacher.name, "email": teacher.email},
    }


# ============== COURSES ==============
@app.post("/courses/create")
def create_course(
    name: str = Form(...),
    code: str = Form(...),
    teacher_id: int = Form(...),
    db: Session = Depends(get_db),
):
    course = models.Course(name=name, code=code, teacher_id=teacher_id)
    db.add(course)
    db.commit()
    db.refresh(course)
    return {"id": course.id, "name": course.name, "code": course.code}


@app.get("/courses/{teacher_id}")
def list_courses(teacher_id: int, db: Session = Depends(get_db)):
    courses = db.query(models.Course).filter_by(teacher_id=teacher_id).all()
    return [{"id": c.id, "name": c.name, "code": c.code} for c in courses]
@app.get("/encodings/{course_id}")
def get_encodings(course_id: int):
    if course_id not in encodings_store:
        return {"success": False, "msg": "No encodings generated for this course"}
    
    encoded_students = []
    for student_id, data in encodings_store[course_id].items():
        encoded_students.append({
            "student_id": student_id,
            "roll_no": data["roll_no"],
            "name": data["name"],
            "encoding_len": len(data["encoding"]) if data.get("encoding") is not None else 0
        })
    
    return {"success": True, "students": encoded_students}

@app.get("/attendance/list/{course_id}")
def list_attendance(course_id: int, db: Session = Depends(get_db)):
    """
    Returns today's attendance list for all students in a course.
    """
    today = datetime.date.today().isoformat()

    # Get all students of the course
    students = db.query(models.Student).filter_by(course_id=course_id).all()

    # Get all attendance records of today for this course
    attendance_records = (
        db.query(models.Attendance)
        .filter(models.Attendance.course_id == course_id, models.Attendance.date == today)
        .all()
    )

    # Map student_id → attendance
    att_map = {a.student_id: a for a in attendance_records}

    result = []
    for s in students:
        att = att_map.get(s.id)
        result.append({
            "student_id": s.id,
            "roll_no": s.roll_no,
            "name": s.name,
            "status": att.status if att else "Absent",   # Default Absent if no record
            "date": att.date if att else today,
            "time": att.time if att else None,
        })

    return {"course_id": course_id, "attendance": result}

# ============== STUDENTS ==============
@app.post("/students/add/{course_id}")
async def add_student(
    course_id: int,
    roll_no: str = Form(...),
    name: str = Form(...),
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    # unique roll in a course
    existing = (
        db.query(models.Student)
        .filter(models.Student.course_id == course_id, models.Student.roll_no == roll_no)
        .first()
    )
    if existing:
        return {"success": False, "msg": f"Roll No {roll_no} already exists in this course."}

    folder = os.path.join(STUDENT_IMG_DIR, f"course_{course_id}")
    os.makedirs(folder, exist_ok=True)
    file_path = os.path.join(folder, image.filename)

    with open(file_path, "wb") as f:
        f.write(await image.read())

    student = models.Student(
        roll_no=roll_no,
        name=name,
        image_path=file_path,
        course_id=course_id,
    )
    db.add(student)
    db.commit()
    db.refresh(student)

    return {
        "success": True,
        "student": {"id": student.id, "roll_no": student.roll_no, "name": student.name},
    }




@app.post("/encodings/{course_id}")
def generate_encodings(course_id: int, db: Session = Depends(get_db)):
    students = db.query(models.Student).filter_by(course_id=course_id).all()
    encodings_store[course_id] = {}

    for s in students:
        if not s.image_path or not os.path.exists(s.image_path):
            continue
        img = cv2.imread(s.image_path)
        if img is None:
            continue
        faces = model.get(img)
        if len(faces) > 0:
            enc = faces[0].normed_embedding
            encodings_store[course_id][s.id] = {
                "roll_no": s.roll_no,
                "name": s.name,
                "encoding": enc,
            }

    # 🔑 Save to file
    os.makedirs("encodings", exist_ok=True)
    with open(f"encodings/course_{course_id}_encodings.pkl", "wb") as f:
        pickle.dump(encodings_store[course_id], f)

    return {"success": True, "count": len(encodings_store[course_id])}



@app.post("/attendance/{course_id}")
def take_attendance(
    course_id: int,
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    # decode image
    content = image.file.read()
    np_arr = np.frombuffer(content, np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    faces = model.get(img)

    today = datetime.date.today().isoformat()
    time_now = datetime.datetime.now().strftime("%H:%M:%S")

    present_ids: set[int] = set()
    refs = encodings_store.get(course_id, {})

    for f in faces:
        emb = f.normed_embedding
        best_id, best_score = None, -1.0
        for sid, ref_emb in refs.items():
            score = float(np.dot(emb, ref_emb["encoding"]))
            if score > best_score:
                best_score, best_id = score, sid
        if best_id is not None and best_score > 0.45:
            present_ids.add(best_id)

    # write + collect statuses
    students = db.query(models.Student).filter_by(course_id=course_id).all()
    present_names = []
    students_status = []
    for s in students:
        status = "Present" if s.id in present_ids else "Absent"
        if status == "Present":
            present_names.append(f"{s.roll_no} - {s.name}")
        students_status.append({
            "id": s.id,
            "roll_no": s.roll_no,
            "name": s.name,
            "status": status
        })

        att = (
            db.query(models.Attendance)
            .filter(
                and_(
                    models.Attendance.student_id == s.id,
                    models.Attendance.course_id == course_id,
                    models.Attendance.date == today,
                )
            )
            .first()
        )
        if not att:
            att = models.Attendance(
                course_id=course_id,
                student_id=s.id,
                date=today,
                time=time_now,
                status=status,
            )
            db.add(att)
        else:
            att.status = status
            att.time = time_now

    db.commit()

    return {
        "success": True,
        "present": len(present_ids),
        "present_names": present_names,
        "students": students_status,          # 👈 Flutter uses this
    }

@app.post("/attendance/video/{course_id}")
def take_attendance_video(
    course_id: int,
    video: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    today = datetime.date.today().isoformat()
    time_now = datetime.datetime.now().strftime("%H:%M:%S")

    tmp_path = os.path.join(UPLOAD_DIR, f"temp_{video.filename}")
    with open(tmp_path, "wb") as f:
        shutil.copyfileobj(video.file, f)

    cap = cv2.VideoCapture(tmp_path)
    present_ids: set[int] = set()
    refs = encodings_store.get(course_id, {})

    frame_i = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame_i += 1
        if frame_i % 20 != 0:
            continue

        faces = model.get(frame)
        for face in faces:
            emb = face.normed_embedding
            best_id, best_score = None, -1.0
            for sid, ref_emb in refs.items():
                score = float(np.dot(emb, ref_emb["encoding"]))
                if score > best_score:
                    best_score, best_id = score, sid
            if best_id is not None and best_score > 0.45:
                present_ids.add(best_id)

    cap.release()
    try:
        os.remove(tmp_path)
    except Exception:
        pass

    students = db.query(models.Student).filter_by(course_id=course_id).all()
    present_names = []
    students_status = []
    for s in students:
        status = "Present" if s.id in present_ids else "Absent"
        if status == "Present":
            present_names.append(f"{s.roll_no} - {s.name}")
        students_status.append({
            "id": s.id,
            "roll_no": s.roll_no,
            "name": s.name,
            "status": status
        })

        att = (
            db.query(models.Attendance)
            .filter(
                and_(
                    models.Attendance.student_id == s.id,
                    models.Attendance.course_id == course_id,
                    models.Attendance.date == today,
                )
            )
            .first()
        )
        if not att:
            att = models.Attendance(
                course_id=course_id,
                student_id=s.id,
                date=today,
                time=time_now,
                status=status,
            )
            db.add(att)
        else:
            att.status = status
            att.time = time_now

    db.commit()

    return {
        "success": True,
        "present": len(present_ids),
        "present_names": present_names,
        "students": students_status,          # 👈 Flutter uses this
    }


@app.post("/attendance/update/{course_id}/{student_id}")
def update_attendance(
    course_id: int,
    student_id: int,
    status: str = Form(...),  # "Present" or "Absent"
    db: Session = Depends(get_db),
):
    today = datetime.date.today().isoformat()
    time_now = datetime.datetime.now().strftime("%H:%M:%S")

    att = (
        db.query(models.Attendance)
        .filter(
            and_(
                models.Attendance.course_id == course_id,
                models.Attendance.student_id == student_id,
                models.Attendance.date == today,
            )
        )
        .first()
    )

    if not att:
        att = models.Attendance(
            course_id=course_id,
            student_id=student_id,
            date=today,
            time=time_now,
            status=status,
        )
        db.add(att)
    else:
        att.status = status
        att.time = time_now

    db.commit()
    return {"success": True, "student_id": student_id, "status": status}


@app.get("/attendance/excel/{course_id}")
def export_excel(course_id: int, db: Session = Depends(get_db)):
    students = db.query(models.Student).filter_by(course_id=course_id).all()
    attendance = db.query(models.Attendance).filter_by(course_id=course_id).all()

    wb = Workbook()
    ws = wb.active
    ws.title = "Attendance"
    ws.append(["Roll No", "Name", "Date", "Time", "Status"])

    for att in attendance:
        stu = next((s for s in students if s.id == att.student_id), None)
        if stu:
            ws.append([stu.roll_no, stu.name, att.date, att.time, att.status])

    file_path = os.path.join(UPLOAD_DIR, f"course_{course_id}_attendance.xlsx")
    wb.save(file_path)
    return FileResponse(file_path, filename=f"course_{course_id}_attendance.xlsx")
@app.get("/students/{course_id}")
def list_students(course_id: int, db: Session = Depends(get_db)):
    students = db.query(models.Student).filter_by(course_id=course_id).all()
    course_encs = encodings_store.get(course_id, {})
    return [
        {
            "id": s.id,
            "roll_no": s.roll_no,
            "name": s.name,
            "has_encoding": s.id in course_encs
        }
        for s in students
    ]

# ============== LOAD ENCODINGS AT STARTUP ==============
@app.on_event("startup")
def load_encodings():
    global encodings_store
    os.makedirs("encodings", exist_ok=True)

    for file in os.listdir("encodings"):
        if file.endswith("_encodings.pkl"):
            course_id = int(file.split("_")[1])  # e.g. course_1_encodings.pkl → 1
            with open(os.path.join("encodings", file), "rb") as f:
                encodings_store[course_id] = pickle.load(f)

    print(f"✅ Loaded encodings for {len(encodings_store)} courses at startup.")
