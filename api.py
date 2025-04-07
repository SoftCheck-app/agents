# -*- coding: utf-8 -*-
from flask import Flask, request

app = Flask(__name__)

@app.route('/', methods=['GET', 'POST', 'PUT', 'DELETE'])
def handle_request():
    print(f'\n Nueva petición {request.method} en {request.path}')
    print(f'Headers: {dict(request.headers)}')
    print(f'Cuerpo: {request.data.decode("utf-8", errors="replace")}')
    return 'OK', 200

if __name__ == '__main__':
    app.run(port=5000)
