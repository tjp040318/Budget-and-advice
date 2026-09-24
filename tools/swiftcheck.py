#!/usr/bin/env python3
"""
A static checker for the Swift in this repo.

There is no Swift compiler available in this environment — download.swift.org is
blocked by egress policy — so this cannot type-check anything. What it CAN do is
catch the specific mistakes that are easy to make when writing a lot of Swift by
hand and impossible to see by reading it:

  0. Function-call argument ORDER, for functions declared in this module. Swift
     enforces label order for calls exactly as it does for initialisers.
  1. Memberwise initialiser argument ORDER. Swift requires call-site labels to
     appear in declaration order. Getting this wrong compiles nowhere and reads
     fine. This is the single error class that bit the previous build.
  2. Unknown argument labels — a typo'd or renamed property.
  3. Enum case pattern arity: `case .foo(let a, let b)` against a case that
     carries three associated values.
  4. Brace, paren and bracket balance per file.
  5. Duplicate type declarations across the module.
  6. References to types that are never declared anywhere in the module.
  7. Static member access on module enums and structs — `UnitDatabase.zeus`
     when nothing called `zeus` is declared on it. This is the class of error
     that survives a rename sweep, because it looks like ordinary code.
  8. Accessor keywords used as values. `var id: String { set.rawValue }` on a
     struct with a property named `set` does not compile: the parser reads the
     first token of the accessor block as the `set` accessor and demands a body.
     Reads perfectly; fails at parse time. `self.set` is the fix.
  9. Duplicate bundle-resource filenames. The Xcode project uses filesystem-
     synchronised groups, so every non-source file under a target's folder is
     copied FLAT into the app bundle. Two files that share a basename in
     different subfolders therefore write to the same path, and the build fails
     with "Multiple commands produce ...". Reading the tree never shows this.
 10. The same function declared twice in one type. A paste that lands twice
     reads as ordinary code and fails with "Invalid redeclaration". Only a
     byte-identical signature is flagged, so overloads pass.

    python3 tools/swiftcheck.py            # check everything
    python3 tools/swiftcheck.py --verbose  # list what it parsed

Exit code is non-zero if anything is wrong, so it can gate a commit.
"""

import re, sys, glob, os
from collections import defaultdict

ROOTS = ["Pantheon", "PantheonTests"]

# ---------------------------------------------------------------------------
# Lexing helpers
# ---------------------------------------------------------------------------

def strip_noise(src, mask_strings=False):
    """Remove comments and string literals so braces inside them do not count.

    `mask_strings` keeps a literal's PLACE instead of deleting it: every
    character of it becomes an underscore, newlines excepted. Counting a call's
    arguments needs that — `LessonBeat("a sentence")` collapses to
    `LessonBeat()` under the default and reads as no arguments at all.
    """
    out, i, n = [], 0, len(src)
    in_s = in_ml = in_lc = False
    bc = 0

    def blank(chunk):
        if mask_strings:
            out.append("".join("\n" if ch == "\n" else "_" for ch in chunk))

    while i < n:
        c, nx = src[i], src[i+1] if i+1 < n else ""
        if in_lc:
            if c == "\n": in_lc = False; out.append(c)
            i += 1; continue
        if bc:
            if c == "/" and nx == "*": bc += 1; i += 2; continue
            if c == "*" and nx == "/": bc -= 1; i += 2; continue
            i += 1; continue
        if in_ml:
            if src[i:i+3] == '"""': in_ml = False; blank(src[i:i+3]); i += 3; continue
            blank(c); i += 1; continue
        if in_s:
            if c == "\\": blank(src[i:i+2]); i += 2; continue
            if c == '"': in_s = False
            blank(c); i += 1; continue
        if src[i:i+3] == '"""': in_ml = True; blank(src[i:i+3]); i += 3; continue
        if c == '"': in_s = True; blank(c); i += 1; continue
        if c == "/" and nx == "/": in_lc = True; i += 2; continue
        if c == "/" and nx == "*": bc = 1; i += 2; continue
        out.append(c); i += 1
    return "".join(out)

def split_top_level(argstr):
    """Split a call's argument list on commas that are not nested."""
    parts, depth, cur = [], 0, ""
    for ch in argstr:
        if ch in "([{": depth += 1
        elif ch in ")]}": depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip(): parts.append(cur)
    return [p.strip() for p in parts]

# ---------------------------------------------------------------------------
# Declaration scanning
# ---------------------------------------------------------------------------

# A property wrapper is still a stored property, and it is still part of the
# memberwise init: `@Binding var selection: T` takes a `selection:` argument.
# Without the attribute prefix here, every SwiftUI view built with a binding
# was reported as passing an unknown label — noise that hides real findings.
STORED = re.compile(r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
                    r"(?:public\s+|private\s+|internal\s+|fileprivate\s+)?"
                    r"(?:static\s+)?(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:")
# A `var` with no annotation and a default (`var speaking = false`) is a
# memberwise parameter too, with its default: the label check called
# `IslandKeepOut(plate:callouts:speaking:)` wrong for it (2026-09-23). A `let`
# with a default is not one (it cannot be set twice), and a static never is.
STORED_INFERRED = re.compile(r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
                             r"(?:(?:public|private|internal|fileprivate)(?:\(set\))?\s+)*"
                             r"var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")
COMPUTED_HINT = re.compile(r"\{")
FUNC = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|static\s+|mutating\s+|nonisolated\s+)*func\s")
DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|final\s+)*"
                  r"(struct|class|actor|enum|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_]*)")
# A typealias names a type too (`typealias Transport = …`, the backend client's
# canned-network hook, 2026-09-22).
TYPEALIAS = re.compile(r"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?typealias\s+([A-Za-z_][A-Za-z0-9_]*)")
CASE = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
INIT = re.compile(r"^\s*(?:public\s+|private\s+|internal\s+)?init\s*\(")
# Any init, failable or not, with its modifiers: read in extensions only.
EXT_INIT = re.compile(r"^\s*(?:(?:public|private|internal|fileprivate|convenience)\s+)*init[?!]?\s*\(")
# Labels of the inits declared in extensions, by the extended type's name.
EXT_INIT_LABELS = defaultdict(set)

FUNC_SIG = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+|"
    r"static\s+|mutating\s+|final\s+|nonisolated\s+|@discardableResult\s+)*func\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\(", re.MULTILINE)

def parse_params(sig_body):
    """['from label:', ...] -> the external labels, in order. '_' means unlabelled."""
    labels = []
    for part in split_top_level(sig_body):
        part = part.strip()
        if not part: continue
        head = part.split(":")[0].strip()
        names = head.split()
        labels.append(names[0] if names else "_")
    return labels

def scan(files, verbose=False):
    structs = {}         # name -> {"props": [...], "hasInit": bool, "file": path}
    enum_cases = {}      # EnumName -> {case: arity}
    funcs = {}           # name -> [labels]  (only when unambiguous across the module)
    overloaded = set()
    declared = set()
    errors = []

    for path in files:
        raw = open(path).read()
        src = strip_noise(raw)

        for o, c, label in (("{","}","brace"), ("(",")","paren"), ("[","]","bracket")):
            if src.count(o) != src.count(c):
                errors.append(f"{path}: {label} imbalance ({src.count(o)-src.count(c):+d})")

        # Function signatures, for the call-order check.
        for m in FUNC_SIG.finditer(src):
            fname = m.group(1)
            depth, i = 1, m.end()
            while i < len(src) and depth:
                if src[i] == "(": depth += 1
                elif src[i] == ")": depth -= 1
                i += 1
            if depth: continue
            labels = parse_params(src[m.end():i-1])
            if fname in funcs and funcs[fname] != labels:
                overloaded.add(fname)     # cannot disambiguate by name alone
            funcs[fname] = labels

        lines = src.split("\n")
        stack = []            # [kind, name, indent, member_indent]
        for ln in lines:
            if not ln.strip(): continue
            indent = len(ln) - len(ln.lstrip())
            while stack and indent <= stack[-1][2] and ln.strip().startswith(("struct","class","enum","extension","protocol")):
                stack.pop()

            # The first line inside a declaration sits at its member indent;
            # anything deeper is a body (a local `let width: CGFloat = 300`
            # inside a computed property is not a stored property).
            if stack and stack[-1][3] is None and indent > stack[-1][2]:
                stack[-1][3] = indent

            ta = TYPEALIAS.match(ln)
            if ta:
                declared.add(ta.group(1))
            m = DECL.match(ln)
            if m:
                kind, name = m.group(1), m.group(2)
                stack.append([kind, name, indent, None])
                if kind in ("struct", "class", "actor", "enum", "protocol"):
                    declared.add(name)
                    # `struct GameScreen<Bar: View, Content: View>` declares Bar
                    # and Content as types for the length of the declaration.
                    generics = re.match(r"[^<\n]*<([^>]*)>", ln[m.start(2):])
                    if generics:
                        for part in generics.group(1).split(","):
                            param = part.split(":")[0].strip()
                            if re.fullmatch(r"[A-Z][A-Za-z0-9_]*", param):
                                declared.add(param)
                    if name in structs and kind != "extension":
                        pass
                    if kind == "struct" and name not in structs:
                        structs[name] = {"props": [], "hasInit": False, "file": path}
                    if kind == "enum":
                        enum_cases.setdefault(name, {})
                continue

            if not stack: continue
            kind, name, _, member_indent = stack[-1]

            if kind == "enum":
                cm = CASE.match(ln)
                if cm:
                    inner = ln[ln.index("(")+1:]
                    depth, buf = 1, ""
                    for ch in inner:
                        if ch == "(": depth += 1
                        elif ch == ")":
                            depth -= 1
                            if depth == 0: break
                        buf += ch
                    enum_cases.setdefault(name, {})[cm.group(1)] = len(split_top_level(buf))

            # An init written in an EXTENSION keeps the memberwise one
            # (Swift's rule), so a call may use either set of labels: the
            # Codex's `CodexPageRequest(blueprintID:kind:)` (an
            # `init?` in `extension CodexPageRequest`) was reported as an
            # unknown label on 2026-09-23. Its labels are recorded here and
            # accepted beside the stored properties in `check_calls`.
            if kind == "extension" and EXT_INIT.match(ln):
                inner = ln[ln.index("(") + 1:]
                depth, buf = 1, ""
                for ch in inner:
                    if ch == "(": depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0: break
                    buf += ch
                for param in split_top_level(buf):
                    first = param.strip().split(":")[0].split()
                    if first and first[0] != "_":
                        EXT_INIT_LABELS[name].add(first[0])

            if kind == "struct" and name in structs:
                if INIT.match(ln): structs[name]["hasInit"] = True
                pm = STORED.match(ln) or STORED_INFERRED.match(ln)
                if pm and not FUNC.match(ln) and indent == member_indent:
                    after = ln[pm.end():]
                    # A computed property has a brace on the same line and no '='
                    if "{" in after and "=" not in after.split("{")[0]:
                        continue
                    if pm.group(1) not in structs[name]["props"]:
                        structs[name]["props"].append(pm.group(1))

    for f in overloaded:
        funcs.pop(f, None)
    if verbose:
        for n, d in sorted(structs.items()):
            print(f"  struct {n}: {len(d['props'])} stored, custom init={d['hasInit']}")
        for n, l in sorted(funcs.items()):
            print(f"  func {n}({', '.join(l)})")
    return structs, enum_cases, funcs, declared, errors


def check_func_calls(files, funcs, errors):
    """Labelled call sites must present their labels in declaration order."""
    for path in files:
        src = strip_noise(open(path).read())
        for name, labels in funcs.items():
            if len(labels) < 2: continue
            known = [l for l in labels if l != "_"]
            if len(known) < 2: continue
            for m in re.finditer(r"(?<![A-Za-z0-9_.])" + re.escape(name) + r"\s*\(", src):
                start = m.end(); depth, i = 1, start
                while i < len(src) and depth:
                    if src[i] == "(": depth += 1
                    elif src[i] == ")": depth -= 1
                    i += 1
                if depth: continue
                args = split_top_level(src[start:i-1])
                seen = []
                for a in args:
                    lm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)", a)
                    if lm: seen.append(lm.group(1))
                if len(seen) < 2: continue
                if any(l not in known for l in seen): continue   # not this overload
                order = [known.index(l) for l in seen]
                if order != sorted(order):
                    line = src[:m.start()].count("\n") + 1
                    bad = [seen[k] for k in range(1, len(order)) if order[k] < order[k-1]]
                    errors.append(
                        f"{path}:{line}: {name}(...) arguments out of declaration order "
                        f"at {bad}; the signature is ({', '.join(labels)})")

# ---------------------------------------------------------------------------
# Call-site checks
# ---------------------------------------------------------------------------

def check_calls(files, structs, errors):
    """Memberwise init argument order and label validity."""
    for path in files:
        raw = open(path).read()
        src = strip_noise(raw)
        for name, decl in structs.items():
            if decl["hasInit"] or not decl["props"]:
                continue   # a custom init makes the memberwise order irrelevant
            for m in re.finditer(r"\b" + re.escape(name) + r"\s*\(", src):
                start = m.end()
                depth, i = 1, start
                while i < len(src) and depth:
                    if src[i] == "(": depth += 1
                    elif src[i] == ")": depth -= 1
                    i += 1
                if depth: continue
                args = split_top_level(src[start:i-1])
                if not args: continue
                labels = []
                for a in args:
                    lm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)", a)
                    if lm: labels.append(lm.group(1))
                    else: labels = None; break
                if not labels: continue
                line = src[:m.start()].count("\n") + 1

                extension_labels = EXT_INIT_LABELS.get(name, set())
                if extension_labels and any(l in extension_labels and l not in decl["props"] for l in labels):
                    # A call to an init declared in an extension: its labels
                    # are that init's, not the memberwise order.
                    unknown = [l for l in labels if l not in extension_labels]
                    if unknown:
                        errors.append(f"{path}:{line}: {name}(...) unknown label(s) "
                                      f"{unknown}; stored properties are {decl['props']}, "
                                      f"extension inits take {sorted(extension_labels)}")
                    continue
                unknown = [l for l in labels if l not in decl["props"]]
                if unknown:
                    errors.append(f"{path}:{line}: {name}(...) unknown label(s) "
                                  f"{unknown}; stored properties are {decl['props']}")
                    continue
                order = [decl["props"].index(l) for l in labels]
                if order != sorted(order):
                    bad = [labels[k] for k in range(1, len(order)) if order[k] < order[k-1]]
                    errors.append(
                        f"{path}:{line}: {name}(...) arguments out of declaration order "
                        f"at {bad}; memberwise init requires {decl['props']}")

def check_patterns(files, enum_cases, errors):
    """`case .foo(let a, let b)` must match the case's associated-value count."""
    arity = defaultdict(set)
    for enum, cases in enum_cases.items():
        for c, n in cases.items():
            arity[c].add(n)
    for path in files:
        src = strip_noise(open(path).read())
        for m in re.finditer(r"case\s+\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", src):
            cname = m.group(1)
            if cname not in arity: continue
            start = m.end(); depth, i = 1, start
            while i < len(src) and depth:
                if src[i] == "(": depth += 1
                elif src[i] == ")": depth -= 1
                i += 1
            if depth: continue
            body = src[start:i-1]
            got = len(split_top_level(body))
            if got not in arity[cname] and body.strip() != "":
                line = src[:m.start()].count("\n") + 1
                errors.append(f"{path}:{line}: pattern .{cname}(...) binds {got} value(s); "
                              f"the case declares {sorted(arity[cname])}")

STATIC_MEMBER = re.compile(r"^\s*(?:@\w+\s+)*(?:nonisolated\s+)?(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:nonisolated\s+)?"
                           r"static\s+(?:let|var|func)\s+([A-Za-z_][A-Za-z0-9_]*)")
ENUM_CASE_ANY = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)")

def collect_static_members(files):
    """type name -> set of static members and enum cases declared directly on it.

    Uses an explicit scope stack: a nested type inside an enum used to reset the
    tracker and silently drop every member declared after it, which turned the
    check into pure noise.
    """
    members = defaultdict(set)
    for path in files:
        src = strip_noise(open(path).read())
        stack = []                       # (name, indent)
        for ln in src.split("\n"):
            if not ln.strip(): continue
            indent = len(ln) - len(ln.lstrip())
            while stack and indent <= stack[-1][1]:
                stack.pop()
            m = DECL.match(ln)
            if m:
                stack.append((m.group(2), indent))
                continue
            if not stack: continue
            owner = stack[-1][0]
            sm = STATIC_MEMBER.match(ln)
            if sm: members[owner].add(sm.group(1))
            ec = ENUM_CASE_ANY.match(ln)
            if ec:
                for part in ln.strip()[5:].split(","):
                    nm = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)", part)
                    if nm: members[owner].add(nm.group(1))
    return members

# Compiler-synthesised and protocol-supplied members that no source line declares.
SYNTHESISED = {
    "self", "init", "allCases", "rawValue", "hashValue", "description", "id",
    "count", "first", "last", "min", "max", "zero", "none", "some", "shared",
    "main", "default", "type",
}

def check_static_members(files, members, errors):
    known_types = {t for t, m in members.items() if m}
    for path in files:
        src = strip_noise(open(path).read())
        for m in re.finditer(r"\b([A-Z][A-Za-z0-9_]+)\.([a-z][A-Za-z0-9_]*)\b", src):
            tname, member = m.group(1), m.group(2)
            if tname not in known_types: continue
            if member in members[tname] or member in SYNTHESISED: continue
            line = src[:m.start()].count("\n") + 1
            errors.append(f"{path}:{line}: {tname}.{member} — "
                          f"'{member}' is not declared on {tname}")

# ---------------------------------------------------------------------------
# Rule 12: a line that is the tail of the line above it
# ---------------------------------------------------------------------------

def check_spliced_lines(files, errors):
    """A non-empty line that is a strict suffix of the line before it.

    This is the fingerprint of a botched programmatic edit — a script that
    rewrites a file by slicing on a substring and puts the tail back. It cost
    a CI cycle on 2026-09-09, when splitting the sixty-eight-row family table
    into four literals left

        static let familyRowsEgypt: [FamilyRow] = [
        FamilyRow] = [

    behind. Every brace, bracket and parenthesis still balanced, so the
    balance check and every other rule here passed it; the Swift compiler
    said `cannot assign to immutable expression of type '[FamilyRow].Type'`
    thirty minutes later.

    A real Swift line is essentially never a suffix of the line above: the
    shortest legitimate cases (`}` under `}`, `)` under `)`, a repeated
    `case .foo:`) are excluded by requiring the suffix to be at least four
    characters and the two lines to differ by a prefix that is not only
    whitespace."""
    for path in files:
        lines = open(path).read().splitlines()
        for i in range(1, len(lines)):
            prev, cur = lines[i - 1].strip(), lines[i].strip()
            if len(cur) < 4 or not prev.endswith(cur):
                continue
            if prev == cur:
                continue
            head = prev[: len(prev) - len(cur)]
            if not head.strip():
                continue
            # A continuation line legitimately repeats an operator tail, so
            # only flag a suffix that carries a bracket or an assignment: the
            # shape a sliced declaration leaves behind.
            if not any(t in cur for t in ("] = [", "= [", "] =", "){", ") {")):
                continue
            errors.append(f"{path}:{i + 1}: line is the tail of the line above it "
                          f"({cur!r}) — a split or a paste landed twice")


# ---------------------------------------------------------------------------
# Rule 13: an attribute that binds to the wrong declaration
# ---------------------------------------------------------------------------

def check_orphan_attributes(files, errors):
    """`@discardableResult` (and friends) must sit on a function.

    Swift skips comments when binding an attribute, so inserting a type
    between an attribute and the function it was written for silently
    reattaches it. That is what happened on 2026-09-10: a new `HitColour`
    enum landed between `@discardableResult` and `Juice.impact`, and the
    macOS runner answered thirty minutes later with "'@discardableResult'
    attribute cannot be applied to this declaration". Every brace balanced
    and every name resolved, so nothing here saw it.

    The check: for each of these attributes, find the next line that starts a
    declaration, skipping comments, blank lines and further attributes. If it
    is not a function or an initialiser, the attribute has drifted."""
    FUNCS = ("func ", "static func ", "init(", "init?", "init<", "mutating func ",
             "private func ", "public func ", "internal func ", "fileprivate func ",
             "private static func ", "public static func ", "@objc func ")
    WANT_FUNC = ("@discardableResult", "@inlinable", "@inline(__always)")
    for path in files:
        lines = open(path).read().splitlines()
        for i, raw in enumerate(lines):
            line = raw.strip()
            if line not in WANT_FUNC:
                continue
            for follower in lines[i + 1:]:
                nxt = follower.strip()
                if not nxt or nxt.startswith("//") or nxt.startswith("@"):
                    continue
                if any(nxt.startswith(f) or (" func " in nxt and nxt.endswith("(")) for f in FUNCS):
                    break
                if "func " in nxt.split("(")[0]:
                    break
                errors.append(f"{path}:{i + 1}: {line} binds to '{nxt[:48]}', which is not a function "
                              f"— a declaration was inserted between the attribute and its function")
                break

    # Two result builders on one declaration. The same skipping of comments
    # is how a rewrite doubles an attribute: the old panel's `@ViewBuilder`
    # stayed on the line above the doc comment when the declaration under it
    # was replaced by one that carried its own, and run 163 (2026-09-16)
    # answered "only one result builder attribute can be attached to a
    # declaration" — an hour after a five-second check would have.
    BUILDERS = ("@ViewBuilder", "@ToolbarContentBuilder", "@SceneBuilder",
                "@TableColumnBuilder", "@CommandsBuilder")
    for path in files:
        lines = open(path).read().splitlines()
        for i, raw in enumerate(lines):
            line = raw.strip()
            if line not in BUILDERS:
                continue
            for j, follower in enumerate(lines[i + 1:], start=i + 2):
                nxt = follower.strip()
                if not nxt or nxt.startswith("//"):
                    continue
                if nxt in BUILDERS:
                    errors.append(f"{path}:{j}: {nxt} under {line} at line {i + 1}: only one result "
                                  f"builder attribute can be attached to a declaration — the first "
                                  f"is the old declaration's, left above the comment")
                break


# ---------------------------------------------------------------------------
# Rule 14: a member that landed in the wrong type
# ---------------------------------------------------------------------------

def check_foreign_wrapped_properties(files, errors):
    """A type using another type's @State / @EnvironmentObject property.

    A property wrapper marks a property that belongs to exactly one view: no
    other type can see it and it is never a global or a parameter. So a body
    that reads `store` inside a view that does not declare it has almost
    always been pasted into the wrong type — which is what happened twice on
    2026-09-10, when a scroll rail written for SummonView was appended to the
    end of the file and landed inside RateTableView instead. Braces balanced,
    every name existed somewhere, and the runner replied "cannot find 'store'
    in scope" half an hour later.

    Only wrapped properties are checked, because they are the ones that cannot
    legitimately be anything else. A bare identifier that matches one is
    reported unless the type declares it too, or it appears after a dot.

    Two things are NOT a foreign use, and both cost a false positive before
    they were written down (2026-09-16, the guide overlay):

    - An `extension` at column 0 belongs to NOBODY. The file is split by
      top-level declarations, so an extension's lines used to be attributed
      to whichever type happened to be declared above it — and an
      `extension View` mentioning a `store` parameter was reported against
      the unrelated struct before it. An extension cannot declare a stored
      property anyway, so nothing is lost by skipping them.
    - An argument LABEL. `GuideOverlay(store: game)` is a memberwise
      initialiser, not a read of somebody else's property."""
    WRAPPED = re.compile(r"^\s*@(?:State|StateObject|Binding|EnvironmentObject|Environment|ObservedObject|"
                         r"FocusState|AppStorage|SceneStorage|GestureState)\b[^\n]*?\b(?:var|let)\s+"
                         r"([A-Za-z_][A-Za-z0-9_]*)")
    TYPE = re.compile(r"^(?:public\s+|private\s+|internal\s+|final\s+)*(struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*)")
    EXTENSION = re.compile(r"^(?:public\s+|private\s+|internal\s+)*extension\s+[A-Za-z_]")
    for path in files:
        text = strip_noise(open(path).read())
        lines = text.splitlines()
        # Split the file into top-level type bodies by column-0 declarations.
        bounds = []
        for i, line in enumerate(lines):
            m = TYPE.match(line)
            if m:
                bounds.append((i, m.group(2)))
            elif EXTENSION.match(line):
                # A boundary owned by nobody: the lines after it are checked
                # against no type until the next declaration.
                bounds.append((i, None))
        if len(bounds) < 2:
            continue
        bounds.append((len(lines), None))
        bodies = {}
        for (start, name), (end, _) in zip(bounds, bounds[1:]):
            if name:
                bodies[name] = (start, lines[start:end])
        owners = {}
        for name, (_, body) in bodies.items():
            for line in body:
                m = WRAPPED.match(line)
                if m:
                    owners.setdefault(m.group(1), set()).add(name)
        for prop, holders in owners.items():
            for name, (start, body) in bodies.items():
                if name in holders:
                    continue
                pattern = re.compile(r"(?<![.$\w])" + re.escape(prop) + r"\b(?!\s*:)")
                for offset, line in enumerate(body):
                    if WRAPPED.match(line) or re.match(r"\s*(?:let|var)\s+" + re.escape(prop) + r"\b", line):
                        break
                    if pattern.search(line):
                        errors.append(
                            f"{path}:{start + offset + 1}: '{name}' uses '{prop}', which is a property wrapper "
                            f"declared on {sorted(holders)[0]} — this member probably belongs to that type")
                        break


# ---------------------------------------------------------------------------
# Rule 15: a switch that has not kept up with its enum
# ---------------------------------------------------------------------------

def collect_enum_labels(files):
    """Every enum by SIMPLE name, as (cases, statics, seen). The two are kept
    APART because they answer different questions: a switch must handle every
    CASE and a static member is not one of them (`CampaignDifficulty.split`
    is a function, and folding it in made the switch rule demand a `.split`
    branch), while a leading-dot default value may legally name either. A
    name used by two enums (this module has two `Kind`s and two `Tab`s) is
    counted in `seen` so a caller can drop it rather than guess."""
    cases, statics, seen = {}, {}, {}
    enum_start = re.compile(r"^\s*(?:public\s+|private\s+|internal\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)")
    case_line = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)")
    # `nonisolated static func` is a static too (a pure helper on a
    # @MainActor class, 2026-09-22): the modifier may come before or after
    # the access level.
    static_line = re.compile(r"^\s*(?:nonisolated\s+)?(?:public\s+|private\s+|internal\s+)?(?:nonisolated\s+)?static\s+(?:let|var|func)\s+([A-Za-z_][A-Za-z0-9_]*)")
    for path in files:
        lines = strip_noise(open(path).read()).splitlines()
        current, indent = None, 0
        for line in lines:
            m = enum_start.match(line)
            if m:
                current, indent = m.group(1), len(line) - len(line.lstrip())
                cases.setdefault(current, set())
                statics.setdefault(current, set())
                seen[current] = seen.get(current, 0) + 1
                continue
            if current is None:
                continue
            stripped = line.strip()
            if stripped and (len(line) - len(line.lstrip())) <= indent and not stripped.startswith("case"):
                current = None
                continue
            cm = case_line.match(line)
            if cm:
                for name in cm.group(1).split(","):
                    name = name.strip().split("(")[0]
                    if name:
                        cases[current].add(name)
                continue
            sm = static_line.match(line)
            if sm:
                statics[current].add(sm.group(1))
    return cases, statics, seen


def check_enum_dot_defaults(files, errors):
    """`: SomeEnum = .caseThatIsNotThere`.

    Swift's leading-dot shorthand is only checked by the compiler, and there
    is no compiler here. `SkillIcon`'s `var element: Element = .light` cost a
    whole CI run on 2026-09-15 — the elements are spelled `.ember`, `.tide`,
    `.gale`, `.radiance`, `.umbra`, and the switch rule caught the switch in
    the same file while the default value sailed past it.

    Only a default VALUE with an explicit enum type on the left is checked,
    which is the shape a human writes by hand and gets wrong; an ambiguous
    simple name is dropped the way the switch rule drops one."""
    cases, statics, seen = collect_enum_labels(files)
    labels = {name: cases[name] | statics.get(name, set()) for name in cases}
    site = re.compile(r":\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)*([A-Z][A-Za-z0-9_]*)\??\s*=\s*\.([A-Za-z_][A-Za-z0-9_]*)")
    for path in files:
        lines = strip_noise(open(path).read()).splitlines()
        for i, line in enumerate(lines):
            for m in site.finditer(line):
                enum, label = m.group(1), m.group(2)
                if enum not in labels or seen.get(enum, 0) != 1:
                    continue
                if not labels[enum]:
                    continue
                if label not in labels[enum]:
                    errors.append(f"{path}:{i + 1}: '{enum}' has no member '.{label}' "
                                  f"(its labels: {', '.join('.' + x for x in sorted(labels[enum])[:8])})")


def check_switch_exhaustive(files, errors):
    """A switch over an enum PARAMETER that is missing one of its cases.

    Adding a case to an enum is the cheapest change there is, and it breaks
    every switch that lists cases without a `default`. It broke the build on
    2026-09-10: a `testing` section was added to ShopService.Section for the
    owner's free packs and `ShopView.glyph(for:)` still listed six.

    Matching on case NAMES alone was tried first and was far too noisy — this
    module has two enums called `Tab` and several that share case names, so a
    subset match guessed wrong five times out of six. Instead the type is
    resolved properly, from the signature of the function the switch sits in:
    `func glyph(for candidate: ShopService.Section)` followed by `switch
    candidate` is unambiguous. That is narrower, and it catches the real
    thing without crying wolf, which is the whole bargain of this file."""
    enum_cases_all, _statics, enum_seen = collect_enum_labels(files)

    param = re.compile(r"[(,]\s*(?:[A-Za-z_][A-Za-z0-9_]*\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
                       r"(?:[A-Za-z_][A-Za-z0-9_]*\.)*([A-Za-z_][A-Za-z0-9_]*)")
    for path in files:
        lines = strip_noise(open(path).read()).splitlines()
        for i, line in enumerate(lines):
            m = re.match(r"^\s*switch\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{?\s*$", line)
            if not m:
                continue
            subject = m.group(1)
            # The signature of the function this switch is inside.
            declared_type = None
            for back in range(i - 1, max(-1, i - 40), -1):
                if "func " not in lines[back]:
                    continue
                for pm in param.finditer(lines[back]):
                    if pm.group(1) == subject:
                        declared_type = pm.group(2)
                break
            if declared_type is None or declared_type not in enum_cases_all:
                continue
            if enum_seen.get(declared_type, 0) != 1:
                continue
            depth, labels, has_default, j = 0, set(), False, i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                if lines[j].strip().startswith("default"):
                    has_default = True
                # `case .radiance, .umbra:` lists two labels and only the
                # first follows the word `case`, so take every dotted name on
                # a line that starts a case. Over-collecting here is safe: it
                # can only make the switch look MORE complete, never less.
                if lines[j].strip().startswith("case "):
                    for cm in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)", lines[j]):
                        labels.add(cm.group(1))
                j += 1
                if depth <= 0 and j > i:
                    break
            if has_default:
                continue
            missing = sorted(enum_cases_all[declared_type] - labels)
            if missing:
                errors.append(f"{path}:{i + 1}: switch over {declared_type} does not handle "
                              f"{', '.join('.' + x for x in missing)} and has no default")



# ---------------------------------------------------------------------------
# Rule 16: a property read off a core model that the model does not have
# ---------------------------------------------------------------------------

def check_model_members(files, errors):
    """`player.tower` when Player has no `tower`.

    A save field is added in one file and read in another, and Swift answers
    "value of type 'Player' has no member 'tower'" — but only on the runner,
    thirty minutes later. It happened on 2026-09-10: the Endless Tower kept its
    progress in `player.tower` and the field was never added to Player.

    Only the handful of model types listed below are checked, and only the
    FIRST member after the variable, so `player.units.filter { ... }` tests
    `units` on Player and leaves `filter` to Array. Members are gathered from
    every declaration of the type anywhere in the module — the struct itself,
    its extensions, stored and computed alike — and the variable's type is
    resolved the same careful way rule 15 resolves a switch subject: from the
    signature of the function the line sits in, so a local named `player` of
    some other type is never mistaken for one."""
    # A class is checked here as readily as a struct: `UnitNode` joined the
    # list on 2026-09-10, when a line asking a UnitNode for a `combatant` it
    # does not have (it carries `combatantID` and `side` instead) balanced,
    # resolved every name, passed every other rule and cost a whole runner
    # cycle to learn. The list is deliberately short — these are the types that
    # everything else in the module reaches into.
    MODELS = {"Player", "Unit", "Relic", "UnitNode", "Combatant"}

    members = {name: set() for name in MODELS}
    decl = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|final\s+)*"
                      r"(?:struct|class|extension|enum)\s+([A-Za-z_][A-Za-z0-9_]*)")
    # An access level may carry a setter's (`private(set) var isDefeated =
    # false`): without the `(set)` the rule never saw UnitNode's
    # `isDefeated` and called a real read of it missing (2026-09-23).
    prop = re.compile(r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
                      r"(?:(?:public|private|internal|fileprivate)(?:\(set\))?\s+)*"
                      r"(?:static\s+)?(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:{=]")
    fn = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+|"
                    r"static\s+|mutating\s+|final\s+|@discardableResult\s+)*func\s+"
                    r"([A-Za-z_][A-Za-z0-9_]*)")
    for path_ in files:
        lines = strip_noise(open(path_).read()).splitlines()
        current, indent = None, 0
        for line in lines:
            m = decl.match(line)
            if m:
                current = m.group(1) if m.group(1) in MODELS else None
                indent = len(line) - len(line.lstrip())
                continue
            if current is None:
                continue
            stripped = line.strip()
            if stripped and (len(line) - len(line.lstrip())) <= indent:
                current = None
                continue
            pm = prop.match(line)
            if pm:
                members[current].add(pm.group(1))
                continue
            fm = fn.match(line)
            if fm:
                members[current].add(fm.group(1))

    # A type that inherits from a framework class carries members this file
    # cannot see: `UnitNode` is an `SCNNode`, so `node.position` is real and
    # nothing in the source declares it. These are the inherited names this
    # module actually uses; anything outside the list is still reported, which
    # is the whole point of the rule.
    INHERITED = {
        # SCNNode
        "position", "worldPosition", "simdPosition", "eulerAngles", "orientation",
        "rotation", "scale", "transform", "worldTransform", "pivot", "opacity",
        "isHidden", "name", "parent", "childNodes", "geometry", "light", "camera",
        "constraints", "physicsBody", "categoryBitMask", "renderingOrder",
        "morpher", "skinner", "filters", "addChildNode", "removeFromParentNode",
        "insertChildNode", "childNode", "enumerateChildNodes",
        "enumerateHierarchy", "runAction", "removeAction", "removeAllActions",
        "hasActions", "action", "addAnimation", "removeAnimation",
        "removeAllAnimations", "animationPlayer", "animationKeys", "clone",
        "flattenedClone", "convertPosition", "convertVector", "convertTransform",
        "look", "boundingBox", "boundingSphere", "presentation", "isPaused",
        "castsShadow", "movabilityHint", "entity", "setValue", "value",
        # NSObject, and the odd protocol requirement
        "description", "hash", "isEqual", "copy", "encode", "id",
    }

    # A model with no members found means the parse missed it; checking against
    # an empty set would report every access. Only check what was really read.
    live = {k: v for k, v in members.items() if len(v) >= 5}
    if not live:
        return

    param = re.compile(r"[(,]\s*(?:[A-Za-z_][A-Za-z0-9_]*\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
                       r"(?:inout\s+)?(?:[A-Za-z_][A-Za-z0-9_]*\.)*([A-Za-z_][A-Za-z0-9_]*)")

    # Properties whose ELEMENT is one of the models: `var unitNodes: [UUID:
    # UnitNode]`, `let team: [Unit]`, `var relics: [Relic]?`. A closure run over
    # one of those — `unitNodes.values.filter { $0.side == ... }` — gives `$0`
    # that element type, and that is where the fault this rule was widened for
    # actually lived: a UnitNode asked for a `combatant` inside a filter. A
    # closure's `$0` is invisible to the parameter-list resolver, so without
    # this the rule reads right past the one line it was written to catch.
    collection = re.compile(r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
                            r"(?:public\s+|private(?:\(set\))?\s+|internal\s+|fileprivate\s+)?"
                            r"(?:static\s+)?(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
                            r"\[(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?([A-Za-z_][A-Za-z0-9_]*)\]")
    # Scoped PER FILE, and a name declared twice in one file with different
    # element types is dropped rather than guessed at. A global map was tried
    # first and was hopeless: a `[ResolvedUnit]` called `units` in one screen
    # made every `$0.unit` in every other screen look like a Unit that has no
    # `unit`, which is three false reports out of five.
    element_of_by_file = {}
    for path_ in files:
        found, clashed = {}, set()
        for line in strip_noise(open(path_).read()).splitlines():
            cm = collection.match(line)
            if not cm:
                continue
            name, elem = cm.group(1), cm.group(2)
            if name in found and found[name] != elem:
                clashed.add(name)
            found[name] = elem
        element_of_by_file[path_] = {
            k: v for k, v in found.items() if v in live and k not in clashed
        }

    # `<prop>.filter { $0.x }`, `<prop>.values.map { $0.x }`, `for n in <prop>`
    closure_over = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:\.(?:values|keys))?\s*"
                              r"\.(?:filter|map|compactMap|flatMap|forEach|first|contains|"
                              r"allSatisfy|sorted|min|max|reduce|partition|drop|prefix)\s*[({]")
    for path_ in files:
        lines = strip_noise(open(path_).read()).splitlines()
        typed = {}          # variable name -> model type, from the last signature seen
        for i, line in enumerate(lines):
            if "func " in line:
                typed = {}
                for pm in param.finditer(line):
                    if pm.group(2) in live:
                        typed[pm.group(1)] = pm.group(2)
            # `$0` is whatever the collection on THIS line holds. Scoped to the
            # line so it cannot leak into the next statement, which is the
            # cheapest way to stay honest about a closure's extent.
            line_typed = dict(typed)
            element_of = element_of_by_file.get(path_, {})
            for om in closure_over.finditer(line):
                owner = element_of.get(om.group(1))
                if owner:
                    line_typed["$0"] = owner
            if not line_typed:
                continue
            for vm in re.finditer(r"\$0\.([A-Za-z_][A-Za-z0-9_]*)", line):
                model = line_typed.get("$0")
                if model is None:
                    break
                field = vm.group(1)
                if field in live[model] or field in ("self", "init") or field in INHERITED:
                    continue
                errors.append(f"{path_}:{i + 1}: {model} has no member '{field}' "
                              f"(read as $0.{field} in a closure over {model})")
            for vm in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)", line):
                model = typed.get(vm.group(1))
                if model is None:
                    continue
                field = vm.group(2)
                if field in live[model] or field in ("self", "init") or field in INHERITED:
                    continue
                errors.append(f"{path_}:{i + 1}: {model} has no member '{field}' "
                              f"(read as {vm.group(1)}.{field})")

def check_unknown_types(files, declared, errors):
    """Types used but never declared anywhere in the module."""
    KNOWN = {
        "Int","Double","String","Bool","UUID","Date","Data","Set","Array","Dictionary",
        "Optional","Result","Error","Float","CGFloat","TimeInterval","Void","Any","AnyObject",
        "Codable","Encodable","Decodable","Equatable","Hashable","Identifiable","Sendable",
        "CaseIterable","Comparable","RandomNumberGenerator","LocalizedError","ObservableObject",
        "View","Scene","App","Color","Font","Image","Text","VStack","HStack","ZStack","Button",
        "ScrollView","LazyVGrid","GridItem","NavigationStack", "NavigationLink", "ShareLink", "ProcessInfo", "UIPasteboard", "UInt8", "UnicodeScalar", "Int8", "Mirror", "CAPropertyAnimation", "CGContext", "CGImage", "CGImageAlphaInfo", "CGBitmapInfo", "CGColorSpaceCreateDeviceRGB", "NSValue", "Calendar", "TimeZone", "Locale", "DateComponents", "CodingKey", "Decoder", "Encoder", "TimelineView", "AppStorage", "UserDefaults", "LongPressGesture", "DragGesture", "NSShadow", "SymbolConfiguration", "UIBezierPath", "CFArray", "CGGradient", "NavigationPath", "Path", "StrokeStyle", "SCNPlane", "SCNParticleSystem", "SCNCamera", "SCNLight", "SCNMaterial", "SCNVector4", "SCNTransaction", "SCNMatrix4MakeScale", "SCNMatrix4MakeRotation", "SCNMatrix4Mult", "SCNGeometrySource", "SCNGeometryElement", "MemoryLayout", "Int32", "SCNPyramid", "SCNSphere", "SCNBox","TabView","Picker","Toggle","Spacer",
        "Divider","Circle","Capsule","Rectangle","RoundedRectangle","LinearGradient","GeometryReader",
        "ForEach","Binding","State","StateObject","EnvironmentObject","Published","MainActor",
        "SCNNode","SCNScene","SCNView","SCNVector3","SCNVector4","SCNMatrix4","SCNCamera","SCNLight",
        "SCNMaterial","SCNGeometry","SCNPlane","SCNBox","SCNSphere","SCNCapsule","SCNCone","SCNTorus",
        "SCNCylinder","SCNPyramid","SCNFloor","SCNText","SCNAction","SCNBillboardConstraint","SCNAntialiasingMode",
        "SCNLookAtConstraint","SCNParticleSystem","SCNSceneSource","SCNSkinner","CAAnimation","CAAnimationGroup","UIColor","UIImage",
        "UIFont","UIView","UIViewRepresentable","UITapGestureRecognizer","UIScreen","NSCoder","NSObject",
        "NSAttributedString","UIGraphicsImageRenderer","CGPoint","CGSize","CGRect","Bundle",
        "FileManager","URL","JSONEncoder","JSONDecoder","Timer","AnyCancellable","Task","Notification",
        # Framework symbols added after the pass was first written. Every one of
        # these was a false positive, and 55 of them made --types unusable —
        # noise that loud hides the one real finding it exists to surface.
        "AngularGradient","RadialGradient","EdgeInsets","StrokeStyle","Group","LazyVStack",
        "ScrollViewReader","ToolbarItem","WindowGroup","Label","ViewBuilder","ViewModifier","Shape",
        "ViewThatFits",
        "ButtonStyle","Environment","Configuration","Content","Context","Self","Never",
        # Fix round 4 (2026-09-23): More's switches (GameToggleStyle), the
        # battle overlay's safe-area insets, the reveal's colour space.
        "ToggleStyle","UIEdgeInsets","CGColorSpace","CFTimeInterval","ObjectIdentifier",
        "EllipticalGradient",
        "SCNHitTestSearchMode","SCNMatrix4MakeTranslation","SCNVector3Zero","AnimationImportPolicy",
        # SCNSceneSource.LoadingOption: the importer's options dictionary,
        # typed since every parse goes through ModelLibrary.parseScene.
        "UInt32", "Gesture", "MagnifyGesture", "LoadingOption",
        # The idle is started through a player since 2026-09-17 (SCNNode.startLoop).
        "SCNAnimation","SCNAnimationPlayer",
        "SIMD3", "SIMD4", "Scalar","simd_quatf","simd_float3",
        # SpriteKit, since the unit plates went screen-space (2026-09-11),
        # and the renderer delegate and Core Graphics names they use.
        # CoreText, since the bundled faces are registered at launch (2026-09-12).
        "CoreText","CTFontManagerRegisterFontsForURL","CFError","CFURL","Unmanaged",
        # Foundation's JSON dictionary, which a save test uses to drop keys (2026-09-13).
        "JSONSerialization",
        "NSMutableParagraphStyle",
        # The launch screen's progress model (2026-09-12).
        "ObservedObject","TimelineView",
        "SpriteKit","SKScene","SKNode","SKSpriteNode","SKCropNode","SKTexture","SKAction",
        "SKShapeNode","SKLabelNode","SCNSceneRenderer","SCNSceneRendererDelegate","CGPath",
        # The arena medallion's drawing and geometry (2026-09-24).
        "CGMutablePath","CGLineCap","CGColorSpaceCreateDeviceGray","SCNTube","SCNMaterialProperty",
        "UIGraphicsImageRendererFormat","UIGraphicsImageRendererContext",
        # The memory probe's GPU line (2026-09-24).
        "Metal","MTLDevice","MTLCreateSystemDefaultDevice",
        # One-channel metallic and roughness maps (ModelLibrary, 2026-09-24).
        "Accelerate","CFData","CGImageSourceCreateWithData","CGImageSourceCreateImageAtIndex",
        "NSCacheDelegate","NSHashTable","NSSelectorFromString",
        "AVFoundation","AVAudioPlayer","AVAudioSession","UIImpactFeedbackGenerator",
        "UINotificationFeedbackGenerator","FeedbackStyle","FeedbackType",
        "UITabBar","UINavigationBar","UserDefaults","NSLock","NSString","Int64","UInt64","Thread","DateFormatter","CFAbsoluteTime","CFAbsoluteTimeGetCurrent","CACurrentMediaTime","RunLoop","PreferenceKey","GeometryProxy","Anchor","CAKeyframeAnimation","SCNParticleBlendMode","SCNParticlePropertyController",
        "ClosedRange","Key","DEBUG","NONE","Menu","AnyView","EmptyView","Namespace",
        "Canvas","GraphicsContext","ScrollViewProxy","UnitCurve","CGVector","Ellipse", "ImageIO", "CFURL", "CFDictionary", "CFString",
        "CGImageSourceCreateWithURL", "CGImageSourceCreateThumbnailAtIndex",
        "kCGImageSourceCreateThumbnailFromImageAlways", "kCGImageSourceCreateThumbnailWithTransform",
        "kCGImageSourceShouldCacheImmediately", "kCGImageSourceThumbnailMaxPixelSize",
        "MenuStyle","Alignment","Anchor","UnitPoint","Axis","Transaction","Animation",
        # The press and the motion tokens (2026-09-24, FEEL.md W1.8): iOS 17's
        # keyframes and springs, and the environment key the press sets.
        "ButtonStyleConfiguration","KeyframeTrack","CubicKeyframe","SpringKeyframe",
        "LinearKeyframe","MoveKeyframe","Spring","EnvironmentKey","EnvironmentValues","KeyframeAnimator",
        # The reveal's Skip follows the finger through the gesture's own state,
        # which SwiftUI resets on a CANCELLED press, where onEnded never comes
        # (2026-09-24, FEEL.md W2.23).
        "GestureState",
        "XCTest","XCTestCase","XCTAssert","XCTAssertEqual","XCTAssertNotEqual","XCTAssertTrue",
        "XCTAssertFalse","XCTAssertNil","XCTAssertNotNil","XCTAssertGreaterThan",
        "XCTAssertGreaterThanOrEqual","XCTAssertLessThan","XCTAssertLessThanOrEqual",
        "XCTAssertThrowsError","XCTAssertNoThrow","XCTFail","XCTUnwrap",
        "XCTestCase","DispatchQueue","NSNumber","Combine","SwiftUI","Foundation","SceneKit","UIKit",
        # CloudKit, since the social layer went on its public database
        # (2026-09-17, Docs/SOCIAL.md), the Foundation query types it takes,
        # the hand-written Codable a grant needed to ride in a mail, the
        # calendar's zone the war's week is computed in, and the text field
        # the friend search and the guild board type into.
        "CloudKit","CKContainer","CKDatabase","CKRecord","CKQuery","CKError","NSPredicate","NSSortDescriptor",
        "Encoder","Decoder","CodingKey","TimeZone","TextField",
        # Sign in with Apple and the cloud save (2026-09-17, evening; the
        # accounts): AuthenticationServices' credential, provider, request,
        # controller and error types and SwiftUI's system button, CryptoKit's
        # SHA-256 for the save's storage key, and CloudKit's asset for a save
        # too big for a record field.
        "AuthenticationServices","ASAuthorization","ASAuthorizationAppleIDCredential",
        "ASAuthorizationAppleIDProvider","ASAuthorizationAppleIDRequest","ASAuthorizationController",
        "ASAuthorizationError","ASAuthorizationRequest","ASPresentationAnchor","SignInWithAppleButton",
        "CryptoKit","SHA256","CKAsset","CKRecordZone","CKAccountStatus",
        # The Supabase backend over URLSession (2026-09-22, Docs/BACKEND.md):
        # Foundation's request, response, URL parts, the plist reader, the
        # ISO-8601 formatter Postgres's stamps are read with, and UTF8 for
        # `String(decoding:as:)`.
        "URLSession","URLRequest","HTTPURLResponse","URLComponents","URLQueryItem",
        "PropertyListSerialization","ISO8601DateFormatter","UTF8",
        # The premium pass (2026-09-22): a type-erased fill for a `?:` of two
        # ShapeStyles, and the Gradient a Canvas shading takes.
        "AnyShapeStyle","Gradient",
        # The chapter map's haze (2026-09-23, round 5): Core Image's clamped
        # blur and the gradient stops a feather mask is built from.
        "CoreImage","CIContext","CIImage","CIFilter","CIVector","CIColor","Stop",
        # The settings side (2026-09-23, Docs/SETTINGS.md): local
        # notifications, iOS's Reduce Motion and the app's own URL opening,
        # the Apple re-authorisation an account deletion asks for, and the
        # weak-keyed tables and associated object the graphics governor keeps
        # its changes in.
        "UserNotifications","UNUserNotificationCenter","UNMutableNotificationContent",
        "UNCalendarNotificationTrigger","UNNotificationRequest","UIApplication","UIWindowScene",
        "UIAccessibility","ASAuthorizationControllerDelegate",
        "ASAuthorizationControllerPresentationContextProviding","NSMapTable","NSCache",
        "OBJC_ASSOCIATION_RETAIN_NONATOMIC",
        # The Treasury (2026-09-23, Docs/STORE.md): StoreKit 2's product,
        # its signed-transaction wrapper, the App Store's sync and payment
        # switch, and its error type. `Transaction` is above (SwiftUI's name
        # too).
        "StoreKit","Product","VerificationResult","AppStore","StoreKitError",
        # The anonymous play data (2026-09-23, Docs/ANALYTICS.md): the app's
        # comings and goings, which start and end a session, the background
        # task the last upload runs under, and the XCTest probe that keeps a
        # test run from sending.
        "NotificationCenter","UIBackgroundTaskIdentifier","NSClassFromString",
        # Crashes and memory that report themselves (2026-09-24,
        # CrashReporter/MemoryProbe): MetricKit's manager, subscriber,
        # payloads, crash diagnostic and call-stack tree; the observer token
        # NotificationCenter hands back; Notification.Name; GCD's memory-
        # pressure and timer sources; and the Mach constants task_info reads
        # the process footprint with.
        "MetricKit","MXMetricManager","MXMetricManagerSubscriber","MXMetricPayload",
        "MXDiagnosticPayload","MXCrashDiagnostic","MXCallStackTree","NSObjectProtocol","Name",
        "DispatchSource","KERN_SUCCESS","TASK_VM_INFO",
    }
    used = defaultdict(list)
    for path in files:
        src = strip_noise(open(path).read())
        for m in re.finditer(r"\b([A-Z][A-Za-z0-9_]{2,})\b", src):
            t = m.group(1)
            if t in KNOWN or t in declared: continue
            used[t].append((path, src[:m.start()].count("\n") + 1))
    for t, sites in sorted(used.items()):
        if len(sites) >= 1:
            path, line = sites[0]
            errors.append(f"{path}:{line}: '{t}' is used but never declared in the module "
                          f"({len(sites)} use(s)) — typo, or missing from the allow-list")

# ---------------------------------------------------------------------------
# Rule 8: a property named like an accessor, used bare inside an accessor block
# ---------------------------------------------------------------------------

# `{ set.rawValue }` is parsed as the start of a setter, not as a member access
# on a property called `set`. Same for get/willSet/didSet. Qualify with `self.`.
ACCESSOR_AS_VALUE = re.compile(
    r"\{\s*(get|set|willSet|didSet)\s*(?=[.\[(?!])")


def check_accessor_keywords(files, errors):
    for path in files:
        src = strip_noise(open(path, encoding="utf-8", errors="replace").read())
        for m in ACCESSOR_AS_VALUE.finditer(src):
            line = src.count("\n", 0, m.start()) + 1
            word = m.group(1)
            errors.append(
                f"{path}:{line}: `{word}` opens this accessor block, so it is parsed "
                f"as the {word} accessor, not as the property named `{word}` — "
                f"write `self.{word}`")



# ---------------------------------------------------------------------------
# Rule: a constant or variable named with a reserved word
# ---------------------------------------------------------------------------
#
# `let internal = info.internal / 1_048_576` (MemoryProbe.breakdown, run 249,
# 2026-09-24) is "keyword 'internal' cannot be used as an identifier here" to
# the compiler, and every later read of the name is an error of its own. A
# MEMBER of that name is fine after a dot (`info.internal`, SE-0071); the
# binding needs another name or backticks. `self` is left out: `guard let
# self` is legal.

RESERVED_WORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "operator",
    "private", "precedencegroup", "protocol", "public", "rethrows", "static",
    "struct", "subscript", "typealias", "var", "break", "case", "catch",
    "continue", "default", "defer", "do", "else", "fallthrough", "for",
    "guard", "if", "in", "repeat", "return", "throw", "switch", "where",
    "while", "Any", "as", "false", "is", "nil", "super", "throws", "true",
    "try",
}
KEYWORD_BINDING = re.compile(
    r"\b(?:let|var)\s+(" + "|".join(sorted(RESERVED_WORDS)) + r")\b(?!`)")


def check_keyword_bindings(files, errors):
    for path in files:
        src = strip_noise(open(path, encoding="utf-8", errors="replace").read())
        for m in KEYWORD_BINDING.finditer(src):
            line = src.count("\n", 0, m.start()) + 1
            word = m.group(1)
            errors.append(
                f"{path}:{line}: `{word}` is a Swift keyword and cannot name a "
                f"constant or variable — rename it, or write it `{word}` in "
                f"backticks everywhere it is used")


# ---------------------------------------------------------------------------
# Rule 12: a local declared twice in one scope
# ---------------------------------------------------------------------------
#
# `let landing = ...` twice in the same block is "invalid redeclaration" to
# the compiler and cost a CI run on 2026-09-15 (the second one was added by
# a later edit that never saw the first). Scopes are counted by braces after
# the noise is stripped; a `switch`'s cases are separate scopes, as they are
# in Swift; `if let` / `guard let` / `for` bind in the block they open, so
# only a declaration that starts its own line counts, plus a `guard let`,
# which binds in the enclosing scope.

DECL_LINE = re.compile(r"^\s*(?:guard\s+)?(?:let|var)\s+([A-Za-z_]\w*)\b")
CASE_LINE = re.compile(r"^\s*(?:case\b.*|default)\s*:\s*(?://.*)?$")


def check_redeclared_locals(files, errors):
    for path in files:
        src = strip_noise(open(path, encoding="utf-8", errors="replace").read())
        # Each scope: (kind, {name: line}); kind is "brace", "switch" or "case".
        scopes = [("brace", {})]
        for i, raw in enumerate(src.split("\n")):
            line = raw.strip()
            if not line:
                continue
            # A `case` inside a switch opens a fresh case scope (closing the
            # one before it) — the same name may be bound in every case.
            if CASE_LINE.match(line) and any(k == "switch" for k, _ in scopes):
                while scopes and scopes[-1][0] == "case":
                    scopes.pop()
                scopes.append(("case", {}))
            m = DECL_LINE.match(line)
            declared = m.group(1) if m else None
            if declared in ("_",):
                declared = None
            guarded = line.startswith("guard ")
            # A declaration whose line opens a block (`let x = f() {` in a
            # multi-line `if`, a computed property) binds inside that block.
            binds_inside = declared is not None and line.endswith("{")
            if declared and not binds_inside:
                names = scopes[-1][1]
                if declared in names and not guarded:
                    errors.append(f"{path}:{i + 1}: `{declared}` is declared again in the same scope "
                                  f"(first at line {names[declared]}) — the compiler calls this an invalid "
                                  f"redeclaration; give the second one its own name")
                else:
                    names.setdefault(declared, i + 1)
            # Braces in the order they come: `} else {` closes, then opens.
            for ch in line:
                if ch == "{":
                    scopes.append(("switch" if "switch " in line else "brace", {}))
                elif ch == "}":
                    while len(scopes) > 1 and scopes[-1][0] == "case":
                        scopes.pop()
                    if len(scopes) > 1:
                        scopes.pop()
            if declared and binds_inside:
                scopes[-1][1].setdefault(declared, i + 1)


# ---------------------------------------------------------------------------
# Rule 9: duplicate bundle-resource filenames
# ---------------------------------------------------------------------------

# Compiled as a unit by actool / the Swift driver rather than copied file by
# file, so same-named files inside these are fine.
BUNDLE_EXEMPT_DIRS = (".xcassets", ".xcdatamodeld", ".lproj", ".docc")


def bundle_resources(root):
    """Files under `root` that Xcode copies flat into the product bundle."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if not d.startswith(".")
                       and not d.endswith(BUNDLE_EXEMPT_DIRS)]
        for name in filenames:
            if name.startswith(".") or name.endswith(".swift"):
                continue
            out.append(os.path.join(dirpath, name))
    return out


def check_bundle_resources(errors):
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        by_name = defaultdict(list)
        for p in bundle_resources(root):
            by_name[os.path.basename(p)].append(p)
        for name, paths in sorted(by_name.items()):
            if len(paths) > 1:
                errors.append(
                    f"{root}: {len(paths)} files named '{name}' all copy to "
                    f"<product>/{name} — 'Multiple commands produce' at build time: "
                    + ", ".join(sorted(paths)))


# ---------------------------------------------------------------------------
# Rule 10: the same function declared twice in one type
# ---------------------------------------------------------------------------

FUNC_START = re.compile(
    r"^\s*(?:@\w+\s+)*((?:public\s+|private\s+|internal\s+|fileprivate\s+|static\s+|"
    r"class\s+|mutating\s+|final\s+|override\s+|@discardableResult\s+)*)func\s")


def check_duplicate_funcs(files, errors):
    """Two declarations with the same signature in the same type, in one file.

    Found the hard way: PlaceholderRig.addSilhouetteCue was pasted twice in one
    commit, every earlier rule passed, and the build failed on the phone. Only
    identical signatures (whitespace aside) count, so overloads by parameter
    type or return type are left alone; static and instance methods with the
    same signature may coexist and are keyed apart.
    """
    for path in files:
        src = strip_noise(open(path, encoding="utf-8", errors="replace").read())
        lines = src.split("\n")
        stack = []                       # (kind, name, indent)
        seen = {}                        # (owner, signature) -> first line
        for idx, ln in enumerate(lines):
            if not ln.strip():
                continue
            indent = len(ln) - len(ln.lstrip())
            while stack and indent <= stack[-1][2]:
                stack.pop()
            dm = DECL.match(ln)
            if dm:
                stack.append((dm.group(1), dm.group(2), indent))
                continue
            fm = FUNC_START.match(ln)
            if not fm:
                continue
            if stack and stack[-1][0] == "protocol":
                continue                 # requirements have no body and may be restated
            # The signature runs from `func` to the body's opening brace, across lines.
            sig, depth, j = "", 0, idx
            while j < len(lines):
                for ch in lines[j]:
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    elif ch == "{" and depth == 0:
                        break
                    sig += ch
                else:
                    sig += " "
                    j += 1
                    continue
                break
            if "func" not in sig:
                continue
            sig = re.sub(r"\s+", " ", sig[sig.index("func"):]).strip()
            static = "static " if re.search(r"\b(static|class)\s", fm.group(1) or "") else ""
            owner = stack[-1][1] if stack else "<top level>"
            key = (owner, static + sig)
            if key in seen:
                errors.append(f"{path}:{idx + 1}: `{sig}` is declared again in {owner}; "
                              f"the first is at line {seen[key]} — 'Invalid redeclaration' at build time")
            else:
                seen[key] = idx + 1


# ---------------------------------------------------------------------------
# Rule 17: stored properties in extensions
# ---------------------------------------------------------------------------
# "extensions must not contain stored properties." Found the day the battle
# reckoning's tallies were declared beside the delegate methods that fill
# them, in `extension BattleViewModel: BattleSceneDelegate`, and read as a
# perfectly natural place for them. A property at one indent inside a
# top-level `extension` block with no accessor body on its line is stored:
# `var x: T = v`, `let x = v`, `var x: T`. Static members are allowed there
# and so are computed ones (a `{` on the line, or opening the next).

EXTENSION_OPEN = re.compile(r"^extension\b[^{]*\{\s*$")
STORED_IN_EXTENSION = re.compile(
    r"^    (?:(?:private|fileprivate|internal|public|open)(?:\(set\))?\s+)*"
    r"(?:lazy\s+|weak\s+|unowned\s+)*(var|let)\s+(\w+)\s*(?::\s*[^{=]+?)?\s*(?:=.*)?$")

def check_extension_stored_properties(files, errors):
    for path in files:
        src = strip_noise(open(path, encoding="utf-8", errors="replace").read())
        lines = src.split("\n")
        i = 0
        while i < len(lines):
            if not EXTENSION_OPEN.match(lines[i]):
                i += 1
                continue
            depth, j = 1, i + 1
            while j < len(lines) and depth > 0:
                line = lines[j]
                if depth == 1 and "{" not in line:
                    m = STORED_IN_EXTENSION.match(line)
                    if m:
                        following = lines[j + 1].strip() if j + 1 < len(lines) else ""
                        if not following.startswith("{"):
                            errors.append(
                                f"{path}:{j + 1}: `{m.group(1)} {m.group(2)}` is a stored property "
                                f"inside an extension — Swift refuses it; declare it in the "
                                f"type's own body (the extension can still use it)")
                depth += line.count("{") - line.count("}")
                j += 1
            i = j


# ---------------------------------------------------------------------------
# Required arguments: a call that leaves a parameter with no default unfilled
# ---------------------------------------------------------------------------
#
# `GameScreen { ... }` cost a CI run on 2026-09-16: the screen takes a title,
# a `bar:` builder and a `content:` builder, and one bare trailing closure
# filled exactly one of them. `check_calls` above could not see it — it only
# reads MEMBERWISE inits, and a type with an explicit init is skipped there,
# which is every type in this project that takes a view builder. So this reads
# the explicit init instead, and counts what a call actually supplies:
# parenthesised arguments plus trailing closures, labelled or not.
#
# It is deliberately conservative. A type with two inits is dropped (which one
# a call meant is a type-checking question). Anything that looks like a
# trailing closure is counted as one, so `if Foo(x) { ... }` over-counts and
# stays quiet rather than crying wolf.

# The type is being NAMED, not called: a return type, an annotation, or an
# opaque/existential/cast position. Whatever brace follows is a body.
TYPE_POSITION = re.compile(r"(->|:|\bsome|\bany|\bis|\bas[?!]?|\bwhere|\bthrows)\s*$")

INIT_HEAD = re.compile(
    r"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|"
    r"required\s+|convenience\s+)*init\??\s*(?:<[^>]*>)?\s*\(")


def _balanced(src, start, opener="(", closer=")"):
    """Index just past the closer matching the opener at src[start - 1]."""
    depth, i = 1, start
    while i < len(src) and depth:
        if src[i] == opener: depth += 1
        elif src[i] == closer: depth -= 1
        i += 1
    return i if not depth else -1


def _has_default(part):
    """Is there a top-level '=' in this parameter declaration?"""
    depth = 0
    for i, ch in enumerate(part):
        if ch in "([{": depth += 1
        elif ch in ")]}": depth -= 1
        elif ch == "=" and depth == 0:
            before = part[i-1] if i else ""
            after = part[i+1] if i + 1 < len(part) else ""
            if before not in "=!<>" and after != "=":
                return True
    return False


def collect_inits(files):
    """type name -> number of init parameters with no default, for single-init types."""
    required = {}
    twice = set()
    for path in files:
        src = strip_noise(open(path).read(), mask_strings=True)
        stack, offset = [], 0
        for ln in src.split("\n"):
            line_start, offset = offset, offset + len(ln) + 1
            if not ln.strip(): continue
            indent = len(ln) - len(ln.lstrip())
            while stack and indent <= stack[-1][1]:
                stack.pop()
            m = DECL.match(ln)
            if m:
                stack.append((m.group(2), indent))
                continue
            if not stack: continue
            head = INIT_HEAD.match(ln)
            if not head: continue
            owner = stack[-1][0]
            end = _balanced(src, line_start + head.end())
            if end < 0: continue
            params = split_top_level(src[line_start + head.end():end - 1])
            if owner in required: twice.add(owner)
            required[owner] = sum(1 for p in params if p.strip() and not _has_default(p))
    for name in twice:
        required.pop(name, None)
    return {n: k for n, k in required.items() if k}


def check_required_arguments(files, required, errors):
    for path in files:
        src = strip_noise(open(path).read(), mask_strings=True)
        for name, need in required.items():
            for m in re.finditer(r"\b" + re.escape(name) + r"\s*(\(|\{)", src):
                # Not the declaration itself, and not `case foo(Bar)`.
                before = src[max(0, m.start() - 80):m.start()]
                if re.search(r"\b(struct|class|enum|protocol|extension|case|func)\s+$", before):
                    continue
                if before.rstrip().endswith("."): continue
                # `func f() -> StatusSpec {` and `var x: StatModifier {` name the
                # type in a RETURN or ANNOTATION position, and the brace that
                # follows is a body, not a trailing closure. Counting those bodies
                # as arguments reported six good call sites on 2026-09-16.
                if m.group(1) == "{" and TYPE_POSITION.search(before):
                    continue
                i = m.end()
                supplied = 0
                if m.group(1) == "(":
                    end = _balanced(src, i)
                    if end < 0: continue
                    supplied += len(split_top_level(src[i:end - 1]))
                    i = end
                else:
                    i = m.end() - 1          # sit on the brace
                # Trailing closures, the first unlabelled and the rest named.
                while True:
                    j = i
                    while j < len(src) and src[j] in " \t\n": j += 1
                    if j < len(src) and src[j] == "{":
                        end = _balanced(src, j + 1, "{", "}")
                        if end < 0: break
                        supplied += 1
                        i = end
                        continue
                    lm = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\{", src[i:])
                    if lm:
                        i = i + lm.end()
                        end = _balanced(src, i, "{", "}")
                        if end < 0: break
                        supplied += 1
                        i = end
                        continue
                    break
                if supplied < need:
                    line = src[:m.start()].count("\n") + 1
                    errors.append(
                        f"{path}:{line}: {name}(...) supplies {supplied} argument(s); "
                        f"its init needs {need} with no default")


# ---------------------------------------------------------------------------
# A name the whole tree spells exactly once
# ---------------------------------------------------------------------------
#
# `unseenIntroChapter` cost the same CI run: the property was deleted with the
# guide it belonged to and the one line that READ it stayed behind, which the
# compiler reported as "cannot find 'unseenIntroChapter' in scope". A name a
# type actually owns is written at least twice — once to declare it, once to
# read it — so a name written exactly once, in a slot where only a value can
# stand, is a name nothing declares.

# `let x = name`, wherever it stands — a statement, or a later clause of an
# `if`/`guard` condition list, which is where the 2026-09-16 one stood.
LONELY_SLOTS = [
    re.compile(r"\b(?:var|let)\s+[A-Za-z_][A-Za-z0-9_]*\s*(?::\s*[^=\n]+?)?=\s*"
               r"([a-z][A-Za-z0-9_]{3,})\s*(?=[,){\]]|$)", re.MULTILINE),
    re.compile(r"^\s*return\s+([a-z][A-Za-z0-9_]{3,})\s*$", re.MULTILINE),
    # A name alone on its line: in a view builder that is a view. Round 5's
    # parked summon edit drew `edgeShade` in the circle's ZStack and was
    # stopped before it declared it — "cannot find 'edgeShade' in scope",
    # run 233, which the two slots above could not see.
    re.compile(r"^\s*([a-z][A-Za-z0-9_]{3,})\s*$", re.MULTILINE),
]
LONELY_SKIP = {"self", "true", "false", "super", "nil", "some", "none", "result",
               "break", "continue", "fallthrough", "return", "default", "else"}


def check_lonely_identifiers(files, errors):
    sources = {path: strip_noise(open(path).read(), mask_strings=True) for path in files}
    counts = defaultdict(int)
    for src in sources.values():
        for word in re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", src):
            counts[word] += 1
    for path, src in sources.items():
        for pattern in LONELY_SLOTS:
            for m in pattern.finditer(src):
                name = m.group(1)
                if name in LONELY_SKIP or counts[name] != 1: continue
                line = src[:m.start()].count("\n") + 1
                errors.append(f"{path}:{line}: '{name}' is written once in the whole "
                              f"tree and read as a value here — nothing declares it")


# ---------------------------------------------------------------------------
# A switch identified by its LABELS, when the subject's type cannot be read
# ---------------------------------------------------------------------------
#
# `check_switch_exhaustive` above resolves the subject from the enclosing
# function's parameter list, which is exact and covers most switches. It
# cannot see `for grant in granted { switch grant {`, where the type comes
# from a call's return type — and that is the one that broke the build on
# 2026-09-16 when `ShopService.Grant` grew a `unit` case.
#
# Matching on case NAMES alone was tried in 2026-09-10 and was far too noisy,
# so this is the same idea held to a much higher bar: the labels must be a
# subset of exactly ONE enum in the module, must cover at least four of its
# cases and at least 70% of them, and that enum must have five or more cases.
# A switch that lists three of eight is a deliberate partial match over some
# other type; one that lists nine of ten is a switch that has drifted.

def _case_pattern(stripped):
    """`case .foo(let x): bar.baz` -> `case .foo(let x)`, on the first colon
    that is not inside brackets."""
    depth = 0
    for i, ch in enumerate(stripped):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == ":" and depth == 0:
            return stripped[:i]
    return stripped


SWITCH_MIN_LABELS = 4
SWITCH_MIN_COVERAGE = 0.7
SWITCH_MIN_CASES = 5


def check_switch_by_labels(files, errors):
    enum_cases_all, _statics, enum_seen = collect_enum_labels(files)
    candidates = {
        name: cases for name, cases in enum_cases_all.items()
        if len(cases) >= SWITCH_MIN_CASES and enum_seen.get(name, 0) == 1
    }
    if not candidates:
        return
    for path in files:
        lines = strip_noise(open(path).read()).splitlines()
        for i, line in enumerate(lines):
            if not re.match(r"^\s*switch\s+[A-Za-z_][A-Za-z0-9_.]*\s*\{?\s*$", line):
                continue
            depth, labels, has_default, j = 0, set(), False, i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                stripped = lines[j].strip()
                if stripped.startswith("default"):
                    has_default = True
                if stripped.startswith("case "):
                    # Only the PATTERN, up to the arm's colon. The body of a
                    # one-line arm is full of dotted names — `outcome.drachma`,
                    # `scroll.rawValue` — and collecting those put labels in
                    # the set that no enum has, so the subset test below could
                    # never match and this rule was silent on the very switch
                    # it was written for.
                    for cm in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)", _case_pattern(stripped)):
                        labels.add(cm.group(1))
                j += 1
                if depth <= 0 and j > i:
                    break
            if has_default or len(labels) < SWITCH_MIN_LABELS:
                continue
            fits = [
                name for name, cases in candidates.items()
                if labels <= cases and len(labels) / len(cases) >= SWITCH_MIN_COVERAGE
            ]
            if len(fits) != 1:
                continue
            missing = sorted(candidates[fits[0]] - labels)
            if missing:
                errors.append(
                    f"{path}:{i + 1}: switch reads as {fits[0]} ({len(labels)} of "
                    f"{len(candidates[fits[0]])} cases) but does not handle "
                    f"{', '.join('.' + x for x in missing)}, and has no default")


# ---------------------------------------------------------------------------
# `return nil` from a function that does not return an Optional
# ---------------------------------------------------------------------------
#
# The other half of the same 2026-09-16 build: `ItemArt.amount(for:)` returns
# a plain String, and the new `.unit` case was given `return nil`. Only a
# switch ARM is checked — `case .foo: return nil` on one line — because a bare
# `return nil` deeper in a body may belong to a closure, and this file would
# rather miss one than cry wolf.

FUNC_RETURN = re.compile(
    r"\bfunc\s+[A-Za-z_][A-Za-z0-9_]*\s*(?:<[^>]*>)?\s*\(")
CASE_RETURNS_NIL = re.compile(r"^\s*case\s[^:]*:\s*return\s+nil\s*$")
OPTIONAL_RETURN = re.compile(r"[?!]\s*$|^Any$|^Optional<")


def check_nil_returns(files, errors):
    for path in files:
        src = strip_noise(open(path).read(), mask_strings=True)
        lines = src.splitlines()
        # Line -> the return type of the innermost func whose body holds it.
        owner = {}
        for m in FUNC_RETURN.finditer(src):
            close = _balanced(src, m.end())
            if close < 0:
                continue
            brace = src.find("{", close)
            if brace < 0:
                continue
            tail = src[close:brace]
            if "\n\n" in tail:          # not a signature any more
                continue
            arrow = tail.rfind("->")
            if arrow < 0:
                continue
            ret = tail[arrow + 2:].split(" where ")[0].strip()
            if not ret or OPTIONAL_RETURN.search(ret):
                continue
            end = _balanced(src, brace + 1, "{", "}")
            if end < 0:
                continue
            first = src[:brace].count("\n")
            last = src[:end].count("\n")
            for ln in range(first, last + 1):
                owner[ln] = ret          # innermost wins: later, nested funcs overwrite
        for index, line in enumerate(lines):
            if not CASE_RETURNS_NIL.match(line):
                continue
            ret = owner.get(index)
            if not ret:
                continue
            errors.append(f"{path}:{index + 1}: returns nil from a function "
                          f"declared to return {ret}, which is not Optional")


# ---------------------------------------------------------------------------
# A ternary that picks between two design tokens of DIFFERENT types
# ---------------------------------------------------------------------------
#
# `fill(canReroll ? Theme.goldPlate : Theme.surface)` cost the fourth red run
# of 2026-09-16: `goldPlate` is a LinearGradient and `surface` is a Color, and
# Swift will not unify them. `ShopView`'s price plate has used a `Group { if
# … } else { … }` for this since it was written — the shape was copied from it
# without the reason. Both sides must be known and must differ, so the rule is
# silent on the overwhelmingly common gold-or-grey Color ternary.

STATIC_TYPED = re.compile(
    r"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?static\s+(?:let|var)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z_][A-Za-z0-9_<>., ]*?)\s*(?:=|\{)|=\s*([A-Z][A-Za-z0-9_]*)\s*[({.])")
TOKEN_TERNARY = re.compile(
    r"\?\s*([A-Z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)\s*[),\]]")


def collect_static_types(files):
    """(Type, member) -> the member's Swift type, where it can be read.

    From the annotation when there is one, and otherwise from the name of the
    thing the initialiser calls — `static let surface = Color(hex:)` is a
    Color. A member whose type cannot be read is simply absent, and the rule
    below needs BOTH sides.
    """
    types = {}
    for path in files:
        src = strip_noise(open(path).read(), mask_strings=True)
        stack = []
        for ln in src.split("\n"):
            if not ln.strip():
                continue
            indent = len(ln) - len(ln.lstrip())
            while stack and indent <= stack[-1][1]:
                stack.pop()
            m = DECL.match(ln)
            if m:
                stack.append((m.group(2), indent))
                continue
            if not stack:
                continue
            sm = STATIC_TYPED.match(ln)
            if sm:
                declared = (sm.group(2) or sm.group(3) or "").strip()
                if declared:
                    types[(stack[-1][0], sm.group(1))] = declared
    return types


def check_token_ternaries(files, types, errors):
    for path in files:
        src = strip_noise(open(path).read(), mask_strings=True)
        for m in TOKEN_TERNARY.finditer(src):
            left = types.get((m.group(1), m.group(2)))
            right = types.get((m.group(3), m.group(4)))
            if not left or not right or left == right:
                continue
            line = src[:m.start()].count("\n") + 1
            errors.append(
                f"{path}:{line}: the branches of this '?:' are "
                f"{m.group(1)}.{m.group(2)} ({left}) and {m.group(3)}.{m.group(4)} "
                f"({right}); Swift will not unify them — use a Group with an if/else")


# ---------------------------------------------------------------------------
# A spring written by hand in the chrome
# ---------------------------------------------------------------------------
#
# The menus had grown more than twenty spring settings, one per screen and
# written on the day, so a popup opened three different ways depending on who
# built it (Docs/FEEL.md W1.8, 2026-09-24). The chrome moves on the seven
# `Motion` tokens in Theme.swift now, and this rule keeps it that way: a
# `.spring(`, `.interactiveSpring(` or `.interpolatingSpring(` whose first
# argument is a number, or a SwiftUI `Spring(` built from numbers, anywhere in
# Pantheon/UI is a new curve — name it with a token instead. Theme.swift is
# where the tokens are written. The fight and the reveal are choreography
# timed to a clip or a beam, not chrome, and keep their own numbers:
# Pantheon/UI/Battle/, SummonRevealView.swift and SummoningCircle*.swift.
# Pantheon/App since the same day: the tab bar (RootView.swift) wrote the
# last spring of its own, and moves on `Motion.select` now.

CHROME_ROOT = (os.path.join("Pantheon", "UI") + os.sep, os.path.join("Pantheon", "App") + os.sep)
CHROME_SPRING_EXEMPT = (
    os.path.join("Pantheon", "UI", "Battle") + os.sep,
    os.path.join("Pantheon", "UI", "Common", "Theme.swift"),
    os.path.join("Pantheon", "UI", "Summon", "SummonRevealView.swift"),
    os.path.join("Pantheon", "UI", "Summon", "SummoningCircle"),
)
HAND_SPRING = re.compile(
    r"(?:\.(?:spring|interactiveSpring|interpolatingSpring)|(?<![A-Za-z0-9_.])Spring)"
    r"\(\s*(?:[A-Za-z]+\s*:\s*)?-?(?:\d|\.\d)")


def check_chrome_springs(files, errors):
    for path in files:
        if not path.startswith(CHROME_ROOT) or path.startswith(CHROME_SPRING_EXEMPT):
            continue
        src = strip_noise(open(path).read(), mask_strings=True)
        for m in HAND_SPRING.finditer(src):
            line = src[:m.start()].count("\n") + 1
            errors.append(
                f"{path}:{line}: a spring written by hand in the chrome — use a Motion "
                f"token (Motion.tap, .select, .pop, .panel, .exit, .celebrate, .ambient; "
                f"Theme.swift), or add one there if none fits")


def main():
    files = []
    for r in ROOTS:
        files += sorted(glob.glob(os.path.join(r, "**", "*.swift"), recursive=True))
    if not files:
        print("no swift files found"); return 1
    verbose = "--verbose" in sys.argv
    structs, enum_cases, funcs, declared, errors = scan(files, verbose)
    check_calls(files, structs, errors)
    check_func_calls(files, funcs, errors)
    if "--members" in sys.argv:
        check_static_members(files, collect_static_members(files), errors)
    check_patterns(files, enum_cases, errors)
    check_enum_dot_defaults(files, errors)
    check_accessor_keywords(files, errors)
    check_keyword_bindings(files, errors)
    check_duplicate_funcs(files, errors)
    check_bundle_resources(errors)
    check_spliced_lines(files, errors)
    check_orphan_attributes(files, errors)
    check_foreign_wrapped_properties(files, errors)
    check_switch_exhaustive(files, errors)
    check_model_members(files, errors)
    check_extension_stored_properties(files, errors)
    check_redeclared_locals(files, errors)
    check_required_arguments(files, collect_inits(files), errors)
    check_lonely_identifiers(files, errors)
    check_switch_by_labels(files, errors)
    check_nil_returns(files, errors)
    check_token_ternaries(files, collect_static_types(files), errors)
    check_chrome_springs(files, errors)
    if "--types" in sys.argv:
        check_unknown_types(files, declared, errors)

    print(f"swiftcheck: {len(files)} files, {len(structs)} structs, {len(funcs)} functions, "
          f"{sum(len(v) for v in enum_cases.values())} enum cases with payloads")
    if errors:
        print(f"\n{len(errors)} problem(s):\n")
        for e in errors: print("  " + e)
        return 1
    print("clean")
    return 0

if __name__ == "__main__":
    sys.exit(main())
