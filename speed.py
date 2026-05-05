import time
import math


class SpeedCalculator:
    def __init__(self, meters_per_pixel=0.05, smoothing_alpha=0.35):
        self.prev_positions = {}
        self.prev_times = {}
        self.smoothed_speeds = {}
        self.meters_per_pixel = meters_per_pixel
        self.smoothing_alpha = smoothing_alpha

    def set_calibration(self, meters_per_pixel):
        # Clamp to a sensible minimum to avoid divide/zero-like behavior.
        self.meters_per_pixel = max(float(meters_per_pixel), 1e-6)

    def get_calibration(self):
        return self.meters_per_pixel

    def compute_speed(self, objects):
        """
        Compute speed for each tracked object.
        
        Args:
            objects: dict {id: {"cx": int, "cy": int, ...}} positions
            
        Returns:
            dict: {id: speed_kmh} speeds in km/h
        """
        speeds = {}
        current_time = time.time()

        for id, obj in objects.items():
            cx, cy = obj["cx"], obj["cy"]
            if id in self.prev_positions:
                # Calculate pixel distance
                dx = cx - self.prev_positions[id][0]
                dy = cy - self.prev_positions[id][1]
                distance_pixels = math.hypot(dx, dy)
                
                # Calculate time delta
                dt = current_time - self.prev_times[id]

                # Calculate speed (pixels per second)
                if dt > 0:
                    speed_pixels_per_sec = distance_pixels / dt

                    # Convert to km/h using current calibration.
                    speed_kmh = speed_pixels_per_sec * self.meters_per_pixel * 3.6

                    prev_smoothed = self.smoothed_speeds.get(id, speed_kmh)
                    smoothed = (
                        self.smoothing_alpha * speed_kmh
                        + (1.0 - self.smoothing_alpha) * prev_smoothed
                    )
                    self.smoothed_speeds[id] = smoothed
                    speeds[id] = smoothed
                else:
                    speeds[id] = 0
            else:
                self.smoothed_speeds[id] = 0
                speeds[id] = 0

            # Update position and time
            self.prev_positions[id] = (cx, cy)
            self.prev_times[id] = current_time

        # Remove disappeared objects
        ids_to_remove = [id for id in self.prev_positions.keys() if id not in objects]
        for id in ids_to_remove:
            del self.prev_positions[id]
            del self.prev_times[id]
            if id in self.smoothed_speeds:
                del self.smoothed_speeds[id]

        return speeds
