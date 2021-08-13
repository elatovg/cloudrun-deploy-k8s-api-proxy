FROM mirror.gcr.io/library/python:3.9.1
COPY app /app
WORKDIR /app
RUN pip install -r requirements.txt
EXPOSE  8000
CMD ["python","app.py"]
