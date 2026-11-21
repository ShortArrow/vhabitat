"""Refuse a plate.svg that could do more than draw once the theme inlines it into a page.

Usage: python3 -I tests/plate_check.py <plate.svg>...
Exits 1 and names each refused file and the first reason, or exits 0 when every file is a plain drawing.

A plate is accepted only when it parses as XML with no DOCTYPE, comment, processing instruction or CDATA section,
since the page is parsed as HTML and those constructs end in different places there than in XML. Every element and
attribute must be on the lists below, in the SVG namespace, and fill and stroke are none or currentColor (ADR-0005).
Text is allowed only in title and desc.
"""

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
    """Raise Refused or expat.ExpatError unless data is a plain SVG drawing."""
    parser = expat.ParserCreate(namespace_separator=" ")
    open_elements = []

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

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = text
    parser.StartDoctypeDeclHandler = refuse("a DOCTYPE")
    parser.CommentHandler = refuse("a comment")
    parser.ProcessingInstructionHandler = refuse("a processing instruction")
    parser.StartCdataSectionHandler = refuse("a CDATA section")
    parser.Parse(data, True)


def main(paths):
    refused = False
    for path in paths:
        try:
            with open(path, "rb") as f:
                check(f.read())
        except (Refused, expat.ExpatError) as e:
            print(f"{path}: {e}", file=sys.stderr)
            refused = True
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
