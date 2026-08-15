.PHONY: all iso clean

all: iso

iso:
	@echo "Bulutta ISO Derleme (Önerilen):"
	@echo "1. Bu depoyu GitHub'a push edin."
	@echo "2. Actions sekmesinden derlenen dumanOS-x86_64.iso dosyasını indirin!"
	@echo ""
	@echo "Mac / Yerel Docker ile Derleme:"
	docker build -t dumanos-builder -f builder/Dockerfile .
	docker run --privileged --rm -v $(PWD):/workspace dumanos-builder

clean:
	rm -rf output /tmp/dumanos-build
