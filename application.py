"""
Application entrypoint alias for AWS Elastic Beanstalk, Docker, and WSGI servers.
"""
from main import app

application = app

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=8000)
