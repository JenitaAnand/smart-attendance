import pandas as pd

# Load ground truth
ground_truth = pd.read_csv("ground_truth.csv")  # roll_no, name, present

# Load system predictions (from Excel export)
preds = pd.read_excel("uploads/course_1_attendance.xlsx")

# Merge on roll_no
df = pd.merge(ground_truth, preds, on="roll_no", suffixes=("_true", "_pred"))

# Convert to binary
df["present_true"] = df["present_true"].map({1:"Present", 0:"Absent"})
df["present_pred"] = df["Status"]

TP = ((df["present_true"]=="Present") & (df["present_pred"]=="Present")).sum()
TN = ((df["present_true"]=="Absent") & (df["present_pred"]=="Absent")).sum()
FP = ((df["present_true"]=="Absent") & (df["present_pred"]=="Present")).sum()
FN = ((df["present_true"]=="Present") & (df["present_pred"]=="Absent")).sum()

accuracy = (TP+TN)/(TP+TN+FP+FN)
precision = TP/(TP+FP) if (TP+FP)>0 else 0
recall = TP/(TP+FN) if (TP+FN)>0 else 0
f1 = 2*precision*recall/(precision+recall) if (precision+recall)>0 else 0

print("Accuracy:", accuracy)
print("Precision:", precision)
print("Recall:", recall)
print("F1 Score:", f1)
