.PHONY: all clean

all: README.pdf

README.pdf: README.md texsmith.yaml
	uv run texsmith -t article --build texsmith.yaml README.md

clean:
	rm -rf build README.pdf
