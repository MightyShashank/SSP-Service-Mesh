RUN_ID?=test

build:
	docker build -t ssp-analysis .

run-lvl1:
	docker run --rm \
	-v "$(PWD)/results:/app/results" \
	ssp-analysis python analysis/analyze_lvl1.py --run_id $(RUN_ID)

run-lvl2:
	docker run --rm \
	-v "$(PWD)/results:/app/results" \
	ssp-analysis python analysis/analyze_lvl2.py --run_id $(RUN_ID)

run-lvl3:
	docker run --rm \
	-v "$(PWD)/results:/app/results" \
	ssp-analysis python analysis/analyze_lvl3.py --run_id $(RUN_ID)

run-lvl4:
	docker run --rm \
	-v "$(PWD)/results:/app/results" \
	ssp-analysis python analysis/analyze_lvl4.py --run_id $(RUN_ID)

clean:
	docker rmi ssp-analysis || true