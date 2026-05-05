import math


class Tracker:
    def __init__(self, max_lost=5, match_threshold=80):
        self.objects = {}
        self.id_count = 0
        self.active_id = None
        self.lost_count = 0
        self.max_lost = max_lost
        self.match_threshold = match_threshold

    def update(self, detections):
        """
        Update tracker with new detections.

        Only one object is tracked at a time to reduce CPU overhead.

        Args:
            detections: list of dicts with keys:
                - bbox: (x1, y1, x2, y2)
                - cls: int
                - label: str

        Returns:
            dict: {id: {"cx": int, "cy": int, "bbox": (x1, y1, x2, y2)}}
        """
        new_objects = {}
        current = None

        if self.active_id is not None and self.active_id in self.objects:
            current = self.objects[self.active_id]

        best_det = None
        best_metric = None

        for det in detections:
            x1, y1, x2, y2 = det["bbox"]
            cx = (x1 + x2) // 2
            cy = (y1 + y2) // 2

            if current is not None:
                dist = math.hypot(cx - current["cx"], cy - current["cy"])
                if best_metric is None or dist < best_metric:
                    best_metric = dist
                    best_det = (det, cx, cy)
            else:
                area = (x2 - x1) * (y2 - y1)
                if best_metric is None or area > best_metric:
                    best_metric = area
                    best_det = (det, cx, cy)

        if best_det is not None:
            det, cx, cy = best_det
            if current is not None and best_metric is not None and best_metric < self.match_threshold:
                obj_id = self.active_id
            else:
                obj_id = self.id_count
                self.id_count += 1
                self.active_id = obj_id

            new_objects[obj_id] = {
                "cx": cx,
                "cy": cy,
                "bbox": det["bbox"],
                "cls": det["cls"],
                "label": det["label"],
            }
            self.lost_count = 0
        else:
            self.lost_count += 1
            if self.lost_count >= self.max_lost:
                self.active_id = None

        self.objects = new_objects
        return self.objects
