tf-init:
	docker compose run --rm terraform init

tf-plan:
	docker compose run --rm terraform plan

tf-apply:
	docker compose run --rm terraform apply

tf-destroy:
	docker compose run --rm terraform destroy

tf-fmt:
	docker compose run --rm terraform fmt

tf-validate:
	docker compose run --rm terraform validate
