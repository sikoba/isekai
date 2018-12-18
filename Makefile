isekai: src/isekai.cr $(wildcard src/**/*.cr)
	crystal build src/isekai.cr

.PHONY: test
test: $(wildcard src/**/*.cr) $(wildcard spec/*.cr)
	crystal spec

.PHONY: clean
clean:
	rm isekai
