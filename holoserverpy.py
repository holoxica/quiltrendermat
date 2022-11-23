"""Show quilts on a Looking Glass display using websockets and HoloPlay service
# HoloPlay Service/Looking Glass Bridge communicates
# - over a websocket
# - using the nanomsg next-generation (nng) requester-responder protocol
# - where the payload is encoded using concise binary object representation (CBOR)
"""

from typing import Any, Union
from websocket import WebSocket, enableTrace
import cbor2
import sys, os, socket
import numpy, cv2, struct

hostname = "localhost"
message_id = 0x80000000  # Request IDs must have the most significant bit set
ws = WebSocket()


def ws_init(host="localhost", port=11222) -> (bool, str):
    """Initialise the websocket driver"""
    global ws
    """Initialise the websocket driver"""
    url = f"ws://{host}:{port}/driver"
    # enableTrace(True) # Shows websocket debug information
    try:
        ws.connect(url, subprotocols=["rep.sp.nanomsg.org"])  # The server subprotocol is nanomsg next-generation (NNG) responder
        response = send_init_message("holoserverpy")  # Send an init message and receive a list of all connected devices
        if "error" in response and response["error"] > 0:
            print("Failed to initialise", response)
            return False, "Failed to initialise \n"
        # WARNING: The value of "defaultQuilt" in each device in the list is erronously returned as a string by some versions of HoloPlay Service/Looking Glass Bridge
        # Be sure to write code to check if the value is a string and parse it using json.loads() if it is
        print(response)
    except Exception as e:
        print("Error in initialising ", e)
        return False, "Initialisation error"
    return True, response


def send_init_message(appid: str, onclose: str = "none"):
    """Send an initialisation message"""
    global ws
    cmd = {
        "init": {
            "appid": appid,
            "onclose": onclose
        }
    }
    msg = {"cmd": cmd, "bin": None}
    send_message(msg)
    return decode_message(ws.recv())


def send_message(message: Any):
    """Send a message over the ws"""
    global message_id, ws
    id_bytes = struct.pack("!I",
                           message_id)  # The ! is important - forces big-endian for networking use cases like this
    message_bytes = cbor2.dumps(message)
    ws.send(id_bytes + message_bytes, opcode=2)  # Opcode 2 means this is a binary websocket message

    message_id = message_id + 1  # Increment the message ID every time we send a message


def decode_message(msg: any):
    """Decode a cibor2 message"""
    global message_id
    if not isinstance(msg, bytes):
        return None  # This isn't a binary message

    if len(msg) < 4:
        return None  # The message must always contain at least a message id

    # Really we should check this against our request id, but we only send two messages and wait for a response each time 
    message_id = struct.unpack("!I", msg[:4])[
        0]  # The ! is important - forces big-endian for networking use cases like this
    data = msg[4:]
    return cbor2.loads(data)


def show_quilt(quilt: bytes, vx: int, vy: int, aspect: float, targetDisplay: Union[int, None] = None):
    """Send a quilt with its parameters to the ws driver"""
    global ws
    cmd = {
        "show": {
            "source": "bindata",
            "quilt": {
                "type": "image",
                "settings": {
                    "vx": vx,
                    "vy": vy,
                    "aspect": aspect
                }
            }
        }
    }
    if targetDisplay is not None:
        cmd["show"]["targetDisplay"] = targetDisplay  # Defaults to the first available display if not provided
    msg = {"cmd": cmd, "bin": quilt}
    send_message(msg)
    return decode_message(
        ws.recv())  # If the response structure includes a value for "error" that is greater than 0, see https://docs.lookingglassfactory.com/core/corejs/api/hops-related#error-codes


def mat_quilt(npquilt: numpy.ndarray, vx: int, vy: int, aspect: float):
    """Matlab interface - can't send uint8 directly, need to use np array"""
    im = cv2.imencode(".png", cv2.cvtColor(npquilt, cv2.COLOR_BGR2RGB))[1].tobytes()   # encode png & convert to bytes

    # with open("tmp.png", "wb") as fid:  # tmp file for debugging
    #      fid.write(im)
    #      fid.close()

    response = show_quilt(im, vx, vy, aspect)
    return response


def show_quilt_file(fname: str) -> bool:
    """Load a quilt file, parse it and display it"""
    if not os.path.exists(fname):
        print(f"File {fname} not found")
        return False
    with open(fname, "rb") as f:
        im = f.read()
    fn, ext = fname.rsplit(".", 1)  # strip filename & ext
    if "_qs" in fn and "x" in fn:
        try:
            q = fn.split("_qs")[1]
            qx, asp = q.split("a")
            vxs, vys = qx.split("x")
            vx, vy = int(vxs), int(vys)
            aspect = float(asp)
        except Exception as e:
            print(e)
            return False
    else:
        vx, vy, aspect = 8, 6, 0.75  # take a guess at the params

    response = show_quilt(im, vx, vy, aspect)
    print(response)
    if "error" in response and response["error"] > 0:
        print("Failed to show quilt", response)
        return False
    return True


# Main
if __name__ == '__main__':
    fname = "Holoxica_logo_quilt.png" if len(sys.argv) == 1 else sys.argv[1]
    if len(sys.argv) == 3:
        try:
            ipaddr = socket.gethostbyname(sys.argv[2])  # websocket does not appear to resolve names
            hostname = ipaddr
        except Exception as e:
            print(f"Invalid host, using {hostname} instead")
    status, msg = ws_init(hostname)
    if status:
        print(show_quilt_file(fname))
    ws.close()

