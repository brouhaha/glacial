#!/usr/bin/python3
# Expression parser
# Copyright 2016, 2018 Eric Smith <spacewar@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of version 3 of the GNU General Public License
# as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This file is based on the SimpleCalc.py for pyparsing


from pyparsing import Combine, Forward, Literal, CaselessLiteral, \
    OneOrMore, Optional, \
    ParseException, ParserElement, ParseResults, StringEnd, Word, \
    ZeroOrMore, \
    infixNotation, oneOf, \
    alphas, alphanums, hexnums, nums, opAssoc


class ExpressionParser:

    class UndefinedSymbol(Exception):
        def __init__(self, s):
            self.symbol = s
            super().__init__('Undefined symbol "%s"' % s)


    class RPNItem:
        pass
        
    class RPNInteger(RPNItem):
        def __init__(self, value):
            self.value = value

        def eval(self, symtab):
            return self.value

        def __str__(self):
            return str(self.value)

    class RPNIdentifier(RPNItem):
        def __init__(self, identifier):
            self.identifier = identifier

        def eval(self, symtab):
            if self.identifier not in symtab:
                raise ExpressionParser.UndefinedSymbol(self.identifier)
            return symtab[self.identifier]

        def __str__(self):
            return self.identifier

    class UnaryOp(RPNItem):
        unary_op_fn = { '+': lambda x: x,
                        '-': lambda x: -x,
                        '~': lambda x: ~x,
                        '!': lambda x: not x
                      }
            
        def __init__(self, name, op1):
            self.name = name
            self.fn = self.unary_op_fn[name]
            self.op1 = op1

        def eval(self, symtab):
            if isinstance(self.op1, ExpressionParser.RPNItem):
                op1 = self.op1.eval(symtab)
            else:
                op1 = self.op1
            return self.fn(op1)

        def __str__(self):
            return str(self.op1) + ' u' + self.name

    class BinaryOp(RPNItem):
        binary_op_fn = { '*':  lambda x, y: x * y,
                         '/':  lambda x, y: x // y,
                         '+':  lambda x, y: x + y,
                         '-':  lambda x, y: x - y,
                         '<<': lambda x, y: x << y,
                         '>>': lambda x, y: x >> y,
                         '<=': lambda x, y: x <= y,
                         '<':  lambda x, y: x < y,
                         '>':  lambda x, y: x > y,
                         '>=': lambda x, y: x >= y,
                         '==': lambda x, y: x == y,
                         '!=': lambda x, y: x != y,
                         '&':  lambda x, y: x & y,
                         '|':  lambda x, y: x | y,
                         '^':  lambda x, y: x ^ y,
                       }

        def __init__(self, name, op1, op2):
            self.name = name
            self.fn = self.binary_op_fn[name]
            self.op1 = op1
            self.op2 = op2

        def eval(self, symtab):
            if isinstance(self.op1, ExpressionParser.RPNItem):
                op1 = self.op1.eval(symtab)
            else:
                op1 = self.op1
            if isinstance(self.op2, ExpressionParser.RPNItem):
                op2 = self.op2.eval(symtab)
            else:
                op2 = self.op2
            return self.fn(op1, op2)

        def __str__(self):
            return str(self.op1) + ' ' + str(self.op2) + ' ' + self.name


    # Convert pyparsing infixNotation output with multiple instances of same
    # operator in one list into nested form.
    # Based on:
    #   http://pyparsing.wikispaces.com/share/view/73472016
    @staticmethod
    def nest_operand_pairs(tokens):
        tokens = tokens[0]
        ret = ParseResults(tokens[:3])
        remaining = iter(tokens[3:])
        while True:
            next_pair = (next(remaining,None), next(remaining,None))
            if next_pair == (None, None):
                break
            ret = ParseResults([ret])
            ret += ParseResults(list(next_pair))
        return [ret]

    @staticmethod
    def infix_to_tree(pe):
        if isinstance(pe, int):
            return ExpressionParser.RPNInteger(pe)
        if isinstance(pe, str):
            return ExpressionParser.RPNIdentifier(pe)
        assert isinstance(pe, ParseResults)
        assert 2 <= len(pe) <= 3
        if len(pe) == 2:
            return ExpressionParser.UnaryOp(pe[0],
                                            ExpressionParser.infix_to_tree(pe[1]))
        return ExpressionParser.BinaryOp(pe[1], 
                                         ExpressionParser.infix_to_tree(pe[0]),
                                         ExpressionParser.infix_to_tree(pe[2]))
        
    def __init__(self):
        ParserElement.enablePackrat()
        hexadecimal_integer = Combine(CaselessLiteral('0x') + Word(hexnums)) \
                              .setName('hexadecimal integer') \
                              .setParseAction(lambda *t: int(t[2][0][2:], 16))

        decimal_integer = Word(nums) \
                          .setName('decimal integer') \
                          .setParseAction(lambda t: int(''.join(t)))

        identifier = Word(alphanums + '_$') \
                     .setName('identifier')

        baseExpr = (hexadecimal_integer | decimal_integer | identifier)
    
        operators = [
                      (oneOf('+ - ~ !'), 1, opAssoc.RIGHT, self.nest_operand_pairs),
                      (oneOf('* /'),   2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('+ -'),   2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('<< >>'), 2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('<= < > >='), 2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('== !='), 2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('&'),     2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('^'),     2, opAssoc.LEFT,  self.nest_operand_pairs),
                      (oneOf('|'),     2, opAssoc.LEFT,  self.nest_operand_pairs),
                    ]
                  

        self.expr = infixNotation(baseExpr, operators) + StringEnd()

    def parse(self, s):
        #print('parsing "%s"' % s)
        e = self.expr.parseString(s)[0]
        #print('pared to:', e)
        e = self.infix_to_tree(e)
        #print('evaluation returned', e)
        return e

       


if __name__ == '__main__':
    ep = ExpressionParser()

    symtab = { 'a': 3,
               'b': 5 }

    while True:
        try:
            estr = input('> ')
        except EOFError:
            break
        tree = ep.parse(estr)
        print(str(tree))
        print(tree.eval(symtab))

