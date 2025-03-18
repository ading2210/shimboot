FROM debian:latest

RUN apt-get update && apt-get upgrade -y

WORKDIR /shimboot
COPY . .

ENTRYPOINT [ "./build_complete.sh" ]
