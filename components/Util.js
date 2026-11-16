.pragma library

// Small helpers shared by the QML components.

// The same colour with a different alpha.
function withAlpha(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a);
}
