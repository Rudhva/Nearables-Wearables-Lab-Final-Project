import cv2
import mediapipe as mp
import math
import csv
import time

# ===== ENTER YOUR MEASURED EYE WIDTH =====
REAL_EYE_WIDTH_MM = 100  # CHANGE THIS

mp_face_mesh = mp.solutions.face_mesh

face_mesh = mp_face_mesh.FaceMesh(
    static_image_mode=False,
    max_num_faces=1,
    refine_landmarks=True,
    min_detection_confidence=0.8,
    min_tracking_confidence=0.8
)

cap = cv2.VideoCapture(0)
mm_per_pixel = None

file = open("jaw_data.csv", "w", newline="")
writer = csv.writer(file)
writer.writerow(["Time (s)", "Jaw Opening (mm)", "Confidence (%)"])

start_time = time.time()

print("Jaw tracking with mirrored view + confidence")

while True:
    success, frame = cap.read()
    if not success:
        break

    # ✅ MIRROR VIEW
    frame = cv2.flip(frame, 1)

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = face_mesh.process(rgb)

    if results.multi_face_landmarks:
        face = results.multi_face_landmarks[0]
        h, w, _ = frame.shape

        # Eye calibration
        left_eye = face.landmark[33]
        right_eye = face.landmark[263]

        lx, ly = int(left_eye.x * w), int(left_eye.y * h)
        rx, ry = int(right_eye.x * w), int(right_eye.y * h)

        eye_pixel_width = math.dist((lx, ly), (rx, ry))
        mm_per_pixel = REAL_EYE_WIDTH_MM / eye_pixel_width

        # Jaw landmarks
        upper = face.landmark[13]
        lower = face.landmark[14]

        x1, y1 = int(upper.x * w), int(upper.y * h)
        x2, y2 = int(lower.x * w), int(lower.y * h)

        jaw_pixels = math.dist((x1, y1), (x2, y2))
        jaw_mm = jaw_pixels * mm_per_pixel

        # ✅ CONFIDENCE CALCULATION
        confidence = ((upper.visibility + lower.visibility) / 2) * 100

        elapsed = round(time.time() - start_time, 2)
        writer.writerow([elapsed, jaw_mm, confidence])

        # 🔴 RED VISUALS
        cv2.line(frame, (x1,y1), (x2,y2), (0,0,255), 3)
        cv2.circle(frame, (x1,y1), 6, (0,0,255), -1)
        cv2.circle(frame, (x2,y2), 6, (0,0,255), -1)

        # Display text
        cv2.putText(frame,
                    f"Jaw: {jaw_mm:.2f} mm | Confidence: {confidence:.1f}%",
                    (20,40),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    1,
                    (0,0,255),
                    2)

    cv2.imshow("Jaw Tracker (mm)", frame)

    if cv2.waitKey(1) & 0xFF == 27:
        break

file.close()
cap.release()
cv2.destroyAllWindows()
