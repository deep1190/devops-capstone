"""Minimal, dependency-free Prometheus metrics (text exposition format 0.0.4).

Kept intentionally small so the container image needs only Flask + gunicorn.
Supports labelled counters, gauges and histograms.
"""
import threading

DEFAULT_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)


def _escape(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _fmt(labels):
    if not labels:
        return ""
    return "{" + ",".join(f'{k}="{_escape(v)}"' for k, v in labels) + "}"


class _Metric:
    kind = "untyped"

    def __init__(self, name, help_text, registry):
        self.name = name
        self.help = help_text
        self._lock = threading.Lock()
        registry.register(self)

    @staticmethod
    def _key(labels):
        return tuple(sorted(labels.items()))


class Counter(_Metric):
    kind = "counter"

    def __init__(self, name, help_text, registry):
        super().__init__(name, help_text, registry)
        self._values = {}

    def inc(self, amount=1.0, **labels):
        key = self._key(labels)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + amount

    def get(self, **labels):
        with self._lock:
            return self._values.get(self._key(labels), 0.0)

    def samples(self):
        with self._lock:
            return [f"{self.name}{_fmt(k)} {v}" for k, v in sorted(self._values.items())]


class Gauge(_Metric):
    kind = "gauge"

    def __init__(self, name, help_text, registry):
        super().__init__(name, help_text, registry)
        self._values = {}

    def set(self, value, **labels):
        with self._lock:
            self._values[self._key(labels)] = float(value)

    def inc(self, amount=1.0, **labels):
        key = self._key(labels)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + amount

    def dec(self, amount=1.0, **labels):
        self.inc(-amount, **labels)

    def samples(self):
        with self._lock:
            return [f"{self.name}{_fmt(k)} {v}" for k, v in sorted(self._values.items())]


class Histogram(_Metric):
    kind = "histogram"

    def __init__(self, name, help_text, registry, buckets=DEFAULT_BUCKETS):
        super().__init__(name, help_text, registry)
        self.buckets = tuple(sorted(buckets))
        self._data = {}  # key -> [bucket_counts, sum, count]

    def observe(self, value, **labels):
        key = self._key(labels)
        with self._lock:
            counts, total, n = self._data.setdefault(key, [[0] * len(self.buckets), 0.0, 0])
            for i, upper in enumerate(self.buckets):
                if value <= upper:
                    counts[i] += 1
            self._data[key] = [counts, total + value, n + 1]

    def samples(self):
        out = []
        with self._lock:
            for key, (counts, total, n) in sorted(self._data.items()):
                for upper, c in zip(self.buckets, counts):
                    out.append(f"{self.name}_bucket{_fmt(key + (('le', upper),))} {c}")
                out.append(f"{self.name}_bucket{_fmt(key + (('le', '+Inf'),))} {n}")
                out.append(f"{self.name}_sum{_fmt(key)} {total}")
                out.append(f"{self.name}_count{_fmt(key)} {n}")
        return out


class Registry:
    def __init__(self):
        self._metrics = []

    def register(self, metric):
        self._metrics.append(metric)

    def render(self):
        lines = []
        for m in self._metrics:
            lines.append(f"# HELP {m.name} {m.help}")
            lines.append(f"# TYPE {m.name} {m.kind}")
            lines.extend(m.samples())
        return "\n".join(lines) + "\n"
