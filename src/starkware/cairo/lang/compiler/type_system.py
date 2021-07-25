import dataclasses

from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType, TypeFelt, TypePointer, TypeStruct)
from starkware.cairo.lang.compiler.ast.expr import ExprAssignment, ExprCast, Expression, ExprTuple
from starkware.cairo.lang.compiler.expression_transformer import ExpressionTransformer


def mark_type_resolved(cairo_type: CairoType) -> CairoType:
    """
    Marks the given type as resolved (struct names are absolute).
    This function can be used after parsing a string which is known to contain resolved types.
    """
    if isinstance(cairo_type, TypeFelt):
        return cairo_type
    elif isinstance(cairo_type, TypePointer):
        return dataclasses.replace(cairo_type, pointee=mark_type_resolved(cairo_type.pointee))
    elif isinstance(cairo_type, TypeStruct):
        if cairo_type.is_fully_resolved:
            return cairo_type
        return dataclasses.replace(
            cairo_type,
            is_fully_resolved=True)
    else:
        raise NotImplementedError(f'Type {type(cairo_type).__name__} is not supported.')


def is_type_resolved(cairo_type: CairoType) -> bool:
    """
    Returns true if the type is resolved (struct names are absolute).
    """
    if isinstance(cairo_type, TypeFelt):
        return True
    elif isinstance(cairo_type, TypePointer):
        return is_type_resolved(cairo_type.pointee)
    elif isinstance(cairo_type, TypeStruct):
        return cairo_type.is_fully_resolved
    else:
        raise NotImplementedError(f'Type {type(cairo_type).__name__} is not supported.')


class MarkResolved(ExpressionTransformer):
    def visit_ExprCast(self, expr: ExprCast):
        return dataclasses.replace(
            expr, expr=self.visit(expr.expr), dest_type=mark_type_resolved(expr.dest_type))

    def visit_ExprTuple(self, expr: ExprTuple):
        return dataclasses.replace(
            expr,
            members=dataclasses.replace(
                expr.members,
                args=[
                    ExprAssignment(
                        identifier=item.identifier,
                        expr=self.visit(item.expr),
                        location=item.location)
                    for item in expr.members.args
                ],
            ),
        )


def mark_types_in_expr_resolved(expr: Expression):
    """
    Same as mark_type_resolved() except that it operates on all types within an expression.
    """
    return MarkResolved().visit(expr)
