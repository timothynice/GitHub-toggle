.PHONY: doctor build run install install-system clean

doctor:
	./doctor.sh

build:
	./build.sh

run:
	./run.sh

install:
	./install.sh --launch

install-system:
	./install.sh --system --launch

clean:
	rm -rf build
