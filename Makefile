isekai: src/isekai.cr $(wildcard src/**/*.cr) $(wildcard src/*.cr)
	crystal build src/isekai.cr

.PHONY: test
test: $(wildcard src/**/*.cr) $(wildcard src/*.cr) $(wildcard spec/*.cr)
	crystal spec

.PHONY: container_test
container_test: $(wildcard src/**/*.cr) $(wildcard src/*.cr) $(wildcard spec/*.cr)
	docker run --rm -w $(PWD) -v $(PWD):$(PWD) isekai crystal spec

.PHONY: clean
clean:
	rm isekai
