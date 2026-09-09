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

def strip_noise(src):
    """Remove comments and string literals so braces inside them do not count."""
    out, i, n = [], 0, len(src)
    in_s = in_ml = in_lc = False
    bc = 0
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
            if src[i:i+3] == '"""': in_ml = False; i += 3; continue
            i += 1; continue
        if in_s:
            if c == "\\": i += 2; continue
            if c == '"': in_s = False
            i += 1; continue
        if src[i:i+3] == '"""': in_ml = True; i += 3; continue
        if c == '"': in_s = True; i += 1; continue
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
COMPUTED_HINT = re.compile(r"\{")
FUNC = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|static\s+|mutating\s+)*func\s")
DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|final\s+)*"
                  r"(struct|class|enum|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_]*)")
CASE = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
INIT = re.compile(r"^\s*(?:public\s+|private\s+|internal\s+)?init\s*\(")

FUNC_SIG = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+|"
    r"static\s+|mutating\s+|final\s+|@discardableResult\s+)*func\s+"
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

            m = DECL.match(ln)
            if m:
                kind, name = m.group(1), m.group(2)
                stack.append([kind, name, indent, None])
                if kind in ("struct", "class", "enum", "protocol"):
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

            if kind == "struct" and name in structs:
                if INIT.match(ln): structs[name]["hasInit"] = True
                pm = STORED.match(ln)
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

STATIC_MEMBER = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?"
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
    "current", "main", "default", "type",
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


def check_unknown_types(files, declared, errors):
    """Types used but never declared anywhere in the module."""
    KNOWN = {
        "Int","Double","String","Bool","UUID","Date","Data","Set","Array","Dictionary",
        "Optional","Result","Error","Float","CGFloat","TimeInterval","Void","Any","AnyObject",
        "Codable","Encodable","Decodable","Equatable","Hashable","Identifiable","Sendable",
        "CaseIterable","Comparable","RandomNumberGenerator","LocalizedError","ObservableObject",
        "View","Scene","App","Color","Font","Image","Text","VStack","HStack","ZStack","Button",
        "ScrollView","LazyVGrid","GridItem","NavigationStack", "NavigationLink", "ShareLink", "ProcessInfo", "UIPasteboard", "UInt8", "UnicodeScalar", "Int8", "Mirror", "CAPropertyAnimation", "CGContext", "CGImage", "CGImageAlphaInfo", "CGBitmapInfo", "CGColorSpaceCreateDeviceRGB", "NSValue", "Calendar", "TimelineView", "AppStorage", "UserDefaults", "LongPressGesture", "NSShadow", "SymbolConfiguration", "UIBezierPath", "CFArray", "CGGradient", "NavigationPath", "Path", "StrokeStyle", "SCNPlane", "SCNParticleSystem", "SCNCamera", "SCNLight", "SCNMaterial", "SCNVector4", "SCNTransaction", "SCNMatrix4MakeScale", "SCNPyramid", "SCNSphere", "SCNBox","TabView","Picker","Toggle","Spacer",
        "Divider","Circle","Capsule","Rectangle","RoundedRectangle","LinearGradient","GeometryReader",
        "ForEach","Binding","State","StateObject","EnvironmentObject","Published","MainActor",
        "SCNNode","SCNScene","SCNView","SCNVector3","SCNVector4","SCNMatrix4","SCNCamera","SCNLight",
        "SCNMaterial","SCNGeometry","SCNPlane","SCNBox","SCNSphere","SCNCapsule","SCNCone","SCNTorus",
        "SCNCylinder","SCNPyramid","SCNFloor","SCNText","SCNAction","SCNBillboardConstraint",
        "SCNLookAtConstraint","SCNParticleSystem","SCNSceneSource","SCNSkinner","CAAnimation","CAAnimationGroup","UIColor","UIImage",
        "UIFont","UIView","UIViewRepresentable","UITapGestureRecognizer","UIScreen","NSCoder","NSObject",
        "NSAttributedString","UIGraphicsImageRenderer","CGPoint","CGSize","CGRect","Bundle",
        "FileManager","URL","JSONEncoder","JSONDecoder","Timer","AnyCancellable","Task","Notification",
        # Framework symbols added after the pass was first written. Every one of
        # these was a false positive, and 55 of them made --types unusable —
        # noise that loud hides the one real finding it exists to surface.
        "AngularGradient","RadialGradient","EdgeInsets","StrokeStyle","Group","LazyVStack",
        "ScrollViewReader","ToolbarItem","WindowGroup","Label","ViewBuilder","ViewModifier",
        "ViewThatFits",
        "ButtonStyle","Environment","Configuration","Content","Context","Self","Never",
        "SCNHitTestSearchMode","SCNMatrix4MakeTranslation","SCNVector3Zero","AnimationImportPolicy",
        "SIMD3","simd_quatf","simd_float3",
        "AVFoundation","AVAudioPlayer","AVAudioSession","UIImpactFeedbackGenerator",
        "UINotificationFeedbackGenerator","FeedbackStyle","FeedbackType",
        "UITabBar","UINavigationBar","UserDefaults","NSLock","NSString","Int64","UInt64",
        "ClosedRange","Key","DEBUG","NONE","Menu","AnyView","EmptyView","Namespace",
        "MenuStyle","Alignment","Anchor","UnitPoint","Axis","Transaction","Animation",
        "XCTest","XCTestCase","XCTAssert","XCTAssertEqual","XCTAssertNotEqual","XCTAssertTrue",
        "XCTAssertFalse","XCTAssertNil","XCTAssertNotNil","XCTAssertGreaterThan",
        "XCTAssertGreaterThanOrEqual","XCTAssertLessThan","XCTAssertLessThanOrEqual",
        "XCTAssertThrowsError","XCTAssertNoThrow","XCTFail","XCTUnwrap",
        "XCTestCase","DispatchQueue","NSNumber","Combine","SwiftUI","Foundation","SceneKit","UIKit",
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
    check_accessor_keywords(files, errors)
    check_duplicate_funcs(files, errors)
    check_bundle_resources(errors)
    check_spliced_lines(files, errors)
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
