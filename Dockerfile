FROM alpine:3.17 as build

RUN apk update && apk add zola

WORKDIR /main

COPY . /main

ARG SITE
RUN zola build --base-url ${SITE}


FROM nginx:1.23-alpine

WORKDIR /app

COPY --from=build /main/public /app

RUN cp -Rfv ./* /usr/share/nginx/html

COPY docker/default.conf /etc/nginx/conf.d/