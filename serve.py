import http.server, socketserver, os
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
S(("127.0.0.1",8790), H).serve_forever()
