import pytest

from starkware.cairo.lang.compiler.ast.expr import (
    ExprAddressOf, ExprConst, ExprDot, ExprNeg, ExprOperator, ExprParentheses)
from starkware.cairo.lang.compiler.ast.formatting_utils import FormattingError
from starkware.cairo.lang.compiler.parser import parse_code_element, parse_expr, parse_file


def remove_parentheses(expr):
    """
    Removes the parentheses (ExprParentheses) from an arithmetic expression.
    """
    if isinstance(expr, ExprParentheses):
        return expr.val
    if isinstance(expr, ExprOperator):
        return ExprOperator(a=remove_parentheses(expr.a), op=expr.op, b=remove_parentheses(expr.b))
    if isinstance(expr, ExprAddressOf):
        return ExprAddressOf(expr=remove_parentheses(expr.expr))
    if isinstance(expr, ExprNeg):
        return ExprNeg(val=remove_parentheses(expr.val))
    if isinstance(expr, ExprDot):
        return ExprDot(expr=remove_parentheses(expr.expr), member=expr.member)
    return expr


def test_format_parentheses():
    """
    Tests that format() adds parentheses where required.
    """

    # Call remove_parentheses(parse_expr()) to create an expression tree in the given structure
    # without ExprParentheses.
    assert remove_parentheses(parse_expr('(a + b) * (c - d) * (e * f)')).format() == \
        '(a + b) * (c - d) * e * f'
    assert remove_parentheses(parse_expr('x - (a + b) - (c - d) - (e * f)')).format() == \
        'x - (a + b) - (c - d) - e * f'
    assert remove_parentheses(parse_expr('(a + b) + (c - d) + (e * f)')).format() == \
        'a + b + c - d + e * f'
    assert remove_parentheses(parse_expr('-(a + b + c)')).format() == '-(a + b + c)'
    assert remove_parentheses(parse_expr('a + -b + c')).format() == 'a + (-b) + c'
    assert remove_parentheses(parse_expr('&(a + b)')).format() == '&(a + b)'

    # Test that parentheses are added to non-atomized DotExpr-s.
    assert remove_parentheses(parse_expr('(x * y).z')).format() == '(x * y).z'
    assert remove_parentheses(parse_expr('(-x).y')).format() == '(-x).y'
    assert remove_parentheses(parse_expr('(&x).y')).format() == '(&x).y'

    assert remove_parentheses(parse_expr('&(x.y)')).format() == '&x.y'
    assert remove_parentheses(parse_expr('-(x.y)')).format() == '-x.y'
    assert remove_parentheses(parse_expr('(x.y)*z')).format() == 'x.y * z'
    assert remove_parentheses(parse_expr('x-(y.z)')).format() == 'x - y.z'
    assert remove_parentheses(parse_expr('([x].y).z')).format() == '[x].y.z'

    # Test that parentheses are not added if they were already present.
    assert parse_expr('(a * (b + c))').format() == '(a * (b + c))'
    assert parse_expr('((a * ((b + c))))').format() == '((a * ((b + c))))'


def test_format_parentheses_notes():
    before = """\
(  #    Comment.
         a + b)"""
    after = """\
(  # Comment.
    a + b)"""
    assert parse_expr(before).format() == after

    before = """\
(
         a + b)"""
    after = """\
(
    a + b)"""
    assert parse_expr(before).format() == after

    before = """\
(
      #    Comment.
         a + b)"""
    after = """\
(
    # Comment.
    a + b)"""
    assert parse_expr(before).format() == after

    before = """\
(#    Comment.
      #
      # x.
      # y.
         a + b)"""
    after = """\
(  # Comment.
    #
    # x.
    # y.
    a + b)"""
    assert parse_expr(before).format() == after


def test_format_func_call_notes():
    before = """\
foo(x = 12 # Comment.
)"""
    with pytest.raises(FormattingError, match='Comments inside expressions are not supported'):
        parse_code_element(before).format(allowed_line_length=100)


def test_negative_numbers():
    assert ExprConst(-1).format() == '-1'
    assert ExprNeg(val=ExprConst(val=1)).format() == '-1'
    assert ExprOperator(a=ExprConst(val=-1), op='+', b=ExprConst(val=-2)).format() == '(-1) + (-2)'
    assert ExprOperator(
        a=ExprNeg(val=ExprConst(val=1)),
        op='+',
        b=ExprNeg(val=ExprConst(val=2))).format() == '(-1) + (-2)'


def test_file_format():
    before = """

ap+=[ fp ]
[ap + -1] = [fp]  *  3
 const x=y  +  z
 member x:T.S
 let x= ap-y  +  z
 let y:a.b.c= x



  label  :
[ap] = [fp];  ap ++
tempvar x=y*z+w
  alloc_locals
local     z                     :T*=x
assert x*z+x=    y+y
static_assert   ap + (3 +   7 )+ ap   ==fp
return  (1,[fp],
  [ap +3],)
   fibonacci  (a = 3 , b=[fp +1])
[ap - 1] = [fp]#    This is a comment.
  #This is another comment.
label2:

  jmp rel 17 if [ap+3]!=  0
[fp] = [fp] * [fp]"""
    after = """\
ap += [fp]
[ap + (-1)] = [fp] * 3
const x = y + z
member x : T.S
let x = ap - y + z
let y : a.b.c = x

label:
[ap] = [fp]; ap++
tempvar x = y * z + w
alloc_locals
local z : T* = x
assert x * z + x = y + y
static_assert ap + (3 + 7) + ap == fp
return (1, [fp], [ap + 3])
fibonacci(a=3, b=[fp + 1])
[ap - 1] = [fp]  # This is a comment.

# This is another comment.
label2:
jmp rel 17 if [ap + 3] != 0
[fp] = [fp] * [fp]
"""
    assert parse_file(before).format() == after


def test_file_format_comments():
    before = """

# First line.
[ap] = [ap]


# Separator comment.


[ap] = [ap]
[ap] = [ap]


# Comment before label.
  label  :
[ap] = [ap] #    Inline.
  #This is another
  # comment before label.
label2:#Inline (label).

[ap] = [ap]
label3:
[ap] = [ap]
# End of file comment."""
    after = """\
# First line.
[ap] = [ap]

# Separator comment.

[ap] = [ap]
[ap] = [ap]

# Comment before label.
label:
[ap] = [ap]  # Inline.

# This is another
# comment before label.
label2:  # Inline (label).
[ap] = [ap]

label3:
[ap] = [ap]
# End of file comment.
"""
    assert parse_file(before).format() == after


def test_file_format_comment_spaces():
    before = """
#   First line.
#{spaces}
#   Second line.{spaces}
#Fourth line.
#   Third line.
[ap] = [ap] #    inline comment.
#   First line.
#   Second line.

#   First line.
#   Second line.
[ap] = [ap] #{spaces}
""".format(spaces='   ')
    after = """\
# First line.
#
#   Second line.
# Fourth line.
#   Third line.
[ap] = [ap]  # inline comment.
# First line.
#   Second line.

# First line.
#   Second line.
[ap] = [ap]  #
"""
    assert parse_file(before).format() == after


def test_file_format_hint():
    before = """\
label:
 %{
 x = y
 "[ fp ]"#Python comment is not auto-formatted
  %}#Cairo Comment

    %{
    %} # Empty hint.
"""
    after = """\
label:
%{
    x = y
    "[ fp ]"#Python comment is not auto-formatted
%}  # Cairo Comment

%{
%}  # Empty hint.
"""
    assert parse_file(before).format() == after


def test_file_format_hints_indent():
    before = """\
  %{
  hint1
  hint2
%}
[fp] = [fp]
func f():
  %{

    if a:
        b
%}
[fp] = [fp]
end
"""
    after = """\
%{
    hint1
    hint2
%}
[fp] = [fp]
func f():
    %{
        if a:
            b
    %}
    [fp] = [fp]
end
"""
    assert parse_file(before).format() == after


def test_parse_struct():
    before = """\
struct MyStruct:
x = 5
      y=3
 end # Comment.
"""
    after = """\
struct MyStruct:
    x = 5
    y = 3
end  # Comment.
"""
    assert parse_file(before).format() == after


def test_parse_namespace():
    before = """\
namespace MyNamespace:
x = 5
      y=3
 end # Comment.

namespace MyNamespace2:
 end
"""
    after = """\
namespace MyNamespace:
    x = 5
    y = 3
end  # Comment.

namespace MyNamespace2:
end
"""
    assert parse_file(before).format() == after


def test_parse_func():
    before = """\
[ap] = 1; ap++

func fib():

      [ap] = 2; ap++
      ap += 3
 ret


 end # Comment.

 call fib
"""
    after = """\
[ap] = 1; ap++

func fib():
    [ap] = 2; ap++
    ap += 3
    ret
end  # Comment.

call fib
"""
    assert parse_file(before).format() == after


def test_func_arg_splitting():
    before = """\
func myfunc{x, y, z, w, foo_bar}(a, b, c, foo, bar,
    variable_name_which_is_way_too_long_but_has_to_be_supported, g):
  ret
end
"""
    after = """\
func myfunc{
        x, y, z, w,
        foo_bar}(
        a, b, c, foo,
        bar,
        variable_name_which_is_way_too_long_but_has_to_be_supported,
        g):
    ret
end
"""
    assert parse_file(before).format(allowed_line_length=25) == after


def test_return_splitting():
    before = """\
return (a, b, c, foo, bar,
        variable_name_which_is_way_too_long_but_has_to_be_supported, g)
"""
    after = """\
return (
    a,
    b,
    c,
    foo,
    bar,
    variable_name_which_is_way_too_long_but_has_to_be_supported,
    g)
"""
    assert parse_file(before).format(allowed_line_length=20) == after


def test_func_arg_ret_splitting():
    before = """\
func myfunc(a, b, c, foo, bar,
    variable_name_which_is_way_too_long_but_has_to_be_supported, g)
    -> (x, y, z, a_return_arg_which_is_also_waaaaaaay_too_long, w):
  ret
end
"""
    after = """\
func myfunc(
        a, b, c, foo,
        bar,
        variable_name_which_is_way_too_long_but_has_to_be_supported,
        g) -> (
        x, y, z,
        a_return_arg_which_is_also_waaaaaaay_too_long,
        w):
    ret
end
"""
    assert parse_file(before).format(allowed_line_length=25) == after
    before = """\
func myfunc(a, b, c, foo, bar,
    variable_name_which_is_way_too_long_but_has_to_be_supported, g) ->
    (x, y, z):
  ret
end
"""
    after = """\
func myfunc(
        a, b, c, foo,
        bar,
        variable_name_which_is_way_too_long_but_has_to_be_supported,
        g) -> (x, y, z):
    ret
end
"""
    assert parse_file(before).format(allowed_line_length=25) == after
    before = """\
func myfunc(ab, cd, ef) -> (x, y, z, a_return_arg_which_is_also_waaaaaaay_too_long, w):
  ret
end
"""
    after = """\
func myfunc(
        ab, cd, ef) -> (
        x, y, z,
        a_return_arg_which_is_also_waaaaaaay_too_long,
        w):
    ret
end
"""
    assert parse_file(before).format(allowed_line_length=25) == after


def test_directives():
    code = """\
[ap] = [ap]
# Comment.
%builtins ab cd ef  # Comment.

[fp] = [fp]
"""
    assert parse_file(code).format() == code


def test_if():
    code = """\
if (a + 1) / b == [fp]:
    [ap] = [ap]
end
"""
    assert parse_file(code).format() == code

    code = """\
if (a + 1) / b != 5:
    [ap] = [ap]
else:
    [ap] = [ap]
end
"""
    assert parse_file(code).format() == code


def test_with():
    code = """\
with   a , b  as   c,d  :
    [ap] = [ap]
end
"""
    assert parse_file(code).format() == """\
with a, b as c, d:
    [ap] = [ap]
end
"""
