RUN_ID?=test

build:
	docker build -t ssp-analysis .

run:
	docker run --rm \
	-v "$(PWD)/results:/app/results" \
	ssp-analysis --run_id $(RUN_ID)

clean:
	docker rmi ssp-analysis || true