FROM golang:1.22-alpine AS build

ENV GOTOOLCHAIN=go1.25.3

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/cerbos-adapter ./...

FROM gcr.io/distroless/static-debian12

COPY --from=build /out/cerbos-adapter /cerbos-adapter

EXPOSE 9090

USER nonroot:nonroot

ENTRYPOINT ["/cerbos-adapter"]
