import numpy as np
import cv2

def draw_detections(frame, detections, objects, speeds):
    """
    Draw bounding boxes, IDs, and speeds on frame.
    
    Args:
        frame: input image
        detections: list of (x1, y1, x2, y2) bounding boxes
        objects: dict {id: (cx, cy)} tracked objects
        speeds: dict {id: speed_kmh}
    
    Returns:
        frame: annotated image
    """
    # Draw bounding boxes
    for (x1, y1, x2, y2) in detections:
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
    
    # Draw tracking circles and speeds
    for id, (cx, cy) in objects.items():
        cv2.circle(frame, (cx, cy), 5, (0, 0, 255), -1)
        
        speed = speeds.get(id, 0)
        label = f"ID:{id} {speed:.1f}km/h"
        
        cv2.putText(frame, label, (cx + 10, cy - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)
    
    return frame

def resize_frame(frame, width=640, height=480):
    """Resize frame to standard size."""
    return cv2.resize(frame, (width, height))
