"""
Application entrypoint alias for AWS Elastic Beanstalk, Docker, and WSGI servers.
"""
import os
from main import app

application = app

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    debug_mode = os.environ.get("FLASK_DEBUG", "0").lower() in ("1", "true")
    app.run(debug=debug_mode, host="0.0.0.0", port=port)
