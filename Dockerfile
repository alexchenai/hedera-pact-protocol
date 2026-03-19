FROM python:3.11-alpine
WORKDIR /app
COPY pitch-deck.html index.html
CMD ["python3", "-m", "http.server", "8080"]
EXPOSE 8080
