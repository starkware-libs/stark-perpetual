import re
from typing import Optional

import pytest

from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType, TypeFelt, TypePointer, TypeStruct, TypeTuple)
from starkware.cairo.lang.compiler.identifier_definition import MemberDefinition, StructDefinition
from starkware.cairo.lang.compiler.identifier_manager import IdentifierManager
from starkware.cairo.lang.compiler.parser import parse_expr
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.compiler.type_system import mark_types_in_expr_resolved
from starkware.cairo.lang.compiler.type_system_visitor import CairoTypeError, simplify_type_system

scope = ScopedName.from_string


def simplify_type_system_test(
        orig_expr: str, simplified_expr: str, simplified_type: CairoType,
        identifiers: Optional[IdentifierManager] = None):
    parsed_expr = mark_types_in_expr_resolved(parse_expr(orig_expr))
    assert simplify_type_system(parsed_expr, identifiers=identifiers) == (
        parse_expr(simplified_expr), simplified_type)


def test_type_visitor():
    t = TypeStruct(scope=scope('T'), is_fully_resolved=True)
    t_star = TypePointer(pointee=t)
    t_star2 = TypePointer(pointee=t_star)

    simplify_type_system_test('fp + 3 + [ap]', 'fp + 3 + [ap]', TypeFelt())
    simplify_type_system_test('cast(fp + 3 + [ap], T*)', 'fp + 3 + [ap]', t_star)
    # Two casts.
    simplify_type_system_test('cast(cast(fp, T*), felt)', 'fp', TypeFelt())
    # Cast from T to T.
    simplify_type_system_test('cast([cast(fp, T*)], T)', '[fp]', t)
    # Dereference.
    simplify_type_system_test('[cast(fp, T**)]', '[fp]', t_star)
    simplify_type_system_test('[[cast(fp, T**)]]', '[[fp]]', t)
    # Address of.
    simplify_type_system_test('&([[cast(fp, T**)]])', '[fp]', t_star)
    simplify_type_system_test('&&[[cast(fp, T**)]]', 'fp', t_star2)


def test_type_tuples():
    t = TypeStruct(scope=scope('T'), is_fully_resolved=True)
    t_star = TypePointer(pointee=t)

    # Simple tuple.
    simplify_type_system_test(
        '(fp, [cast(fp, T*)], cast(fp,T*))',
        '(fp, [fp], fp)', TypeTuple(members=[TypeFelt(), t, t_star],))

    # Nested.
    simplify_type_system_test('(fp, (), ([cast(fp, T*)],))', '(fp, (), ([fp],))', TypeTuple(
        members=[
            TypeFelt(),
            TypeTuple(members=[]),
            TypeTuple(members=[t])],
    ))


def test_type_dot_op():
    """
    Tests type_system_visitor for ExprDot-s, in the following struct architecture:

    struct S:
        member x : felt
        member y : felt
    end

    struct T:
        member t : felt
        member s : S
        member sp : S*
    end

    struct R:
        member r : R*
    end
    """
    t = TypeStruct(scope=scope('T'), is_fully_resolved=True)
    s = TypeStruct(scope=scope('S'), is_fully_resolved=True)
    s_star = TypePointer(pointee=s)
    r = TypeStruct(scope=scope('R'), is_fully_resolved=True)
    r_star = TypePointer(pointee=r)

    identifier_dict = {
        scope('T'): StructDefinition(
            full_name=scope('T'),
            members={
                't': MemberDefinition(offset=0, cairo_type=TypeFelt()),
                's': MemberDefinition(offset=1, cairo_type=s),
                'sp': MemberDefinition(offset=3, cairo_type=s_star),
            },
            size=4,
        ),
        scope('S'): StructDefinition(
            full_name=scope('S'),
            members={
                'x': MemberDefinition(offset=0, cairo_type=TypeFelt()),
                'y': MemberDefinition(offset=1, cairo_type=TypeFelt()),
            },
            size=2,
        ),
        scope('R'): StructDefinition(
            full_name=scope('R'),
            members={
                'r': MemberDefinition(offset=0, cairo_type=r_star),
            },
            size=1,
        ),
    }

    identifiers = IdentifierManager.from_dict(identifier_dict)

    simplify_type_system_test(
        '[cast(fp, T*)].t', '[fp]', TypeFelt(),
        identifiers=identifiers)
    simplify_type_system_test(
        '[cast(fp, T*)].s', '[fp + 1]', s,
        identifiers=identifiers)
    simplify_type_system_test(
        '[cast(fp, T*)].sp', '[fp + 3]', s_star,
        identifiers=identifiers)
    simplify_type_system_test(
        '[cast(fp, T*)].s.x', '[fp + 1]', TypeFelt(),
        identifiers=identifiers)
    simplify_type_system_test(
        '[cast(fp, T*)].s.y', '[fp + 1 + 1]', TypeFelt(),
        identifiers=identifiers)
    simplify_type_system_test(
        '[[cast(fp, T*)].sp].x', '[[fp + 3]]', TypeFelt(),
        identifiers=identifiers)
    simplify_type_system_test(
        '[cast(fp, R*)]', '[fp]', r,
        identifiers=identifiers)
    simplify_type_system_test(
        '[cast(fp, R*)].r', '[fp]', r_star,
        identifiers=identifiers)
    simplify_type_system_test(
        '[[[cast(fp, R*)].r].r].r', '[[[fp]]]', r_star,
        identifiers=identifiers)

    # Test . as ->
    simplify_type_system_test(
        'cast(fp, T*).t', '[fp]', TypeFelt(),
        identifiers=identifiers)
    simplify_type_system_test(
        'cast(fp, T*).sp.y', '[[fp + 3] + 1]', TypeFelt(),
        identifiers=identifiers)
    simplify_type_system_test(
        'cast(fp, R*).r.r.r', '[[[fp]]]', r_star,
        identifiers=identifiers)

    # Test failures.

    verify_exception('cast(fp, felt).x', """
file:?:?: Cannot apply dot-operator to non-struct type 'felt'.
cast(fp, felt).x
^**************^
""", identifiers=identifiers)

    verify_exception('cast(fp, felt*).x', """
file:?:?: Cannot apply dot-operator to pointer-to-non-struct type 'felt*'.
cast(fp, felt*).x
^***************^
""", identifiers=identifiers)

    verify_exception('cast(fp, T*).x', """
file:?:?: Member x does not appear in definition of struct 'T'.
cast(fp, T*).x
^************^
""", identifiers=identifiers)

    verify_exception('cast(fp, Z*).x', """
file:?:?: Unknown identifier 'Z'.
cast(fp, Z*).x
^************^
""", identifiers=identifiers)

    verify_exception('cast(fp, T*).x', """
file:?:?: Identifiers must be initialized for type-simplification of dot-operator expressions.
cast(fp, T*).x
^************^
""", identifiers=None)

    verify_exception('cast(fp, Z*).x', """
file:?:?: Type is expected to be fully resolved at this point.
cast(fp, Z*).x
^************^
""", identifiers=identifiers, resolve_types=False)


def test_type_visitor_failures():
    verify_exception('[cast(fp, T*)] + 3', """
file:?:?: Operator '+' is not implemented for types 'T' and 'felt'.
[cast(fp, T*)] + 3
^****************^
""")
    verify_exception('[[cast(fp, T*)]]', """
file:?:?: Cannot dereference type 'T'.
[[cast(fp, T*)]]
^**************^
""")
    verify_exception('[cast(fp, T)]', """
file:?:?: Cannot cast to 'T' since the expression has no address.
[cast(fp, T)]
      ^^
""")
    verify_exception('&(cast(fp, T*) + 3)', """
file:?:?: Expression has no address.
&(cast(fp, T*) + 3)
  ^**************^
""")


def test_type_visitor_pointer_arithmetic():
    t = TypeStruct(scope=scope('T'), is_fully_resolved=True)
    t_star = TypePointer(pointee=t)

    simplify_type_system_test('cast(fp, T*) + 3', 'fp + 3', t_star)
    simplify_type_system_test('cast(fp, T*) - 3', 'fp - 3', t_star)
    simplify_type_system_test('cast(fp, T*) - cast(3, T*)', 'fp - 3', TypeFelt())


def test_type_visitor_pointer_arithmetic_failures():
    verify_exception('cast(fp, T*) + cast(fp, T*)', """
file:?:?: Operator '+' is not implemented for types 'T*' and 'T*'.
cast(fp, T*) + cast(fp, T*)
^*************************^
""")
    verify_exception('cast(fp, T*) - cast(fp, S*)', """
file:?:?: Operator '-' is not implemented for types 'T*' and 'S*'.
cast(fp, T*) - cast(fp, S*)
^*************************^
""")
    verify_exception('fp - cast(fp, T*)', """
file:?:?: Operator '-' is not implemented for types 'felt' and 'T*'.
fp - cast(fp, T*)
^***************^
""")


def verify_exception(
        expr_str: str,
        error: str,
        identifiers: Optional[IdentifierManager] = None,
        resolve_types=True):
    """
    Verifies that calling simplify_type_system() on the code results in the given error.
    """
    with pytest.raises(CairoTypeError) as e:
        parsed_expr = parse_expr(expr_str)
        if resolve_types:
            parsed_expr = mark_types_in_expr_resolved(parsed_expr)
        simplify_type_system(parsed_expr, identifiers)
    # Remove line and column information from the error using a regular expression.
    assert re.sub(':[0-9]+:[0-9]+: ', 'file:?:?: ', str(e.value)) == error.strip()
