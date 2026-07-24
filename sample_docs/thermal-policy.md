# Thermal Policy

Apple Silicon devices can enter elevated thermal states during sustained local inference.

The engine should reduce retrieved context size when thermals become serious and stop new heavy work when thermals are critical.

This protects user experience by avoiding runaway CPU, GPU, and memory pressure during long local model sessions.
