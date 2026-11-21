"""Refuse a plate.svg that could do more than draw once the theme inlines it into a page.

Usage: python3 -I tests/plate_check.py <plate.svg>...
       python3 -I tests/plate_check.py --pages <built page.html>...
Exits 1 and names each refused file and the first reason, or exits 0 when every plate is a plain drawing.
With --pages it checks the plates the theme inlined into built pages, and prints how many it found.

A plate is accepted only when it is UTF-8 with no byte order mark or NUL, the way the page that inlines its bytes is
read, and parses as XML with no DOCTYPE, comment, processing instruction or CDATA section, since the page is parsed
as HTML and those constructs end in different places there than in XML. Every element and
attribute must be on the lists below, in the SVG namespace, and fill and stroke are none or currentColor (ADR-0005).
Text is allowed only in title and desc.
"""

import re
import sys
from xml.parsers import expat

SVG = "http://www.w3.org/2000/svg"
ELEMENTS = {"svg", "g", "path", "circle", "ellipse", "line", "polyline", "polygon", "rect", "title", "desc"}
TEXT_ELEMENTS = {"title", "desc"}
ATTRIBUTES = {
    "viewBox", "width", "height", "transform", "d", "points",
    "cx", "cy", "r", "rx", "ry", "x", "y", "x1", "y1", "x2", "y2",
    "fill", "fill-rule", "fill-opacity", "opacity",
    "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
    "stroke-dasharray", "stroke-dashoffset", "stroke-opacity",
}
PAINTS = {"none", "currentColor"}


class Refused(Exception):
    """A construct a plate may not contain."""


def refuse(what):
    def handler(*_):
        raise Refused(what)
    return handler


def check(data):
    """Raise Refused or expat.ExpatError unless data is a plain SVG drawing in UTF-8."""
    if data.startswith(b"\xef\xbb\xbf") or b"\0" in data:
        raise Refused("a byte order mark or NUL byte")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise Refused(f"bytes that are not UTF-8 ({e.reason})")
    parser = expat.ParserCreate(encoding="UTF-8", namespace_separator=" ")
    open_elements = []

    def declaration(_version, encoding, _standalone):
        if encoding is not None and encoding.upper() not in ("UTF-8", "UTF8"):
            raise Refused(f"encoding {encoding!r}")

    def start(name, attributes):
        namespace, _, local = name.rpartition(" ")
        if namespace != SVG or local not in ELEMENTS:
            raise Refused(f"element {name!r}")
        if not open_elements and local != "svg":
            raise Refused("the root is not svg")
        for attribute, value in attributes.items():
            if attribute not in ATTRIBUTES:
                raise Refused(f"attribute {attribute!r} on {local}")
            if attribute in ("fill", "stroke") and value not in PAINTS:
                raise Refused(f"{attribute}={value!r} on {local}")
        open_elements.append(local)

    def end(_):
        open_elements.pop()

    def text(data):
        if data.strip() and (not open_elements or open_elements[-1] not in TEXT_ELEMENTS):
            raise Refused(f"text in {open_elements[-1] if open_elements else 'the document'}")

    parser.XmlDeclHandler = declaration
    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = text
    parser.StartDoctypeDeclHandler = refuse("a DOCTYPE")
    parser.CommentHandler = refuse("a comment")
    parser.ProcessingInstructionHandler = refuse("a processing instruction")
    parser.StartCdataSectionHandler = refuse("a CDATA section")
    parser.Parse(data, True)


FIGURE = re.compile(rb'<figure class="bestiary-plate">(.*?)</figure>', re.DOTALL)
CAPTION = re.compile(rb"<figcaption>[^<]*</figcaption>\s*$")


def inlined_plates(page):
    """The plates the theme inlined into a built page: each bestiary-plate figure without its caption.

    The theme escapes the caption, so it holds no "<"; anything else left in the figure is the plate's bytes,
    and a plate that ends the figure early leaves a fragment that does not parse.
    """
    return [CAPTION.sub(b"", inner).strip() for inner in FIGURE.findall(page)]


def main(args):
    pages = args[:1] == ["--pages"]
    refused, plates = False, 0
    for path in args[1:] if pages else args:
        with open(path, "rb") as f:
            data = f.read()
        for plate in inlined_plates(data) if pages else [data]:
            plates += 1
            try:
                check(plate)
            except (Refused, expat.ExpatError) as e:
                print(f"{path}: {e}", file=sys.stderr)
                refused = True
    if pages:
        sys.stdout.buffer.write(b"%d\n" % plates)
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
