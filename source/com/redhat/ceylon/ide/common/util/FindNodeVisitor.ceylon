import com.redhat.ceylon.compiler.typechecker.tree {
	Visitor,
	Node,
	Tree {
		Term
	}
}
import java.util {
    List
}
import org.antlr.runtime {
    CommonToken
}

shared class FindNodeVisitor(List<CommonToken>? tokens, Integer startOffset, Integer endOffset) extends Visitor() {
    
	shared variable Node? node = null;
	
	Boolean inBounds(Node? left, Node? right = left) {
		if (exists left) {
			value rightNode = right else left;
			
			assert (is CommonToken? startToken = left.token,
				is CommonToken? endToken = rightNode.endToken else rightNode.token);
			
			if (exists startToken, exists endToken) {
				if (exists tokens) {
					if (startToken.tokenIndex > 0) {
						if (startToken.startIndex > startOffset) {
							// we could still consider this in bounds
							// if the tokens between startOffset and startToken were only hidden ones
							for (index in (startToken.tokenIndex-1)..0) {
								value token = tokens.get(index);
								if (token.channel != CommonToken.\iHIDDEN_CHANNEL) {
									return false;
								}
								if (token.startIndex < startOffset) {
									break;
								}
							}
						}
					}
					if (endToken.tokenIndex < tokens.size() - 1) {
						if (endToken.stopIndex < endOffset) {
							// we could still consider this in bounds
							// if the tokens between endToken and endOffset were only hidden ones
							for (index in (endToken.tokenIndex+1)..(tokens.size()-1)) {
								value token = tokens.get(index);
								if (token.channel != CommonToken.\iHIDDEN_CHANNEL) {
									return false;
								}
								if (token.stopIndex > endOffset) {
									break;
								}
							}
						}
					}
					return true;
				} else {
					if (exists startTokenOffset = left.startIndex?.intValue(),
						exists endTokenOffset = rightNode.stopIndex?.intValue()) {
						return startTokenOffset <= startOffset && endOffset <= endTokenOffset+1;
					} else {
						return false;
					}
				}
			} else {
				return false;
			}
		} else {
			return false;
		}
	}
	
	shared actual void visit(Tree.MemberLiteral that) {
		if (inBounds(that.identifier)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.ExtendedType that) {
		Tree.SimpleType? t = that.type;
		if (exists t) {
			t.visit(this);
		}
		Tree.InvocationExpression? ie = that.invocationExpression;
		if (exists ie, exists args = ie.positionalArgumentList) {
			args.visit(this);
		}
		
		if (!exists t, !exists ie) {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.ClassSpecifier that) {
		Tree.SimpleType? t = that.type;
		if (exists t) {
			t.visit(this);
		}
		Tree.InvocationExpression? ie = that.invocationExpression;
		if (exists ie, exists args = ie.positionalArgumentList) {
			args.visit(this);
		}
		
		if (!exists t, !exists ie) {
			super.visit(that);
		}
	}
	
	shared actual void visitAny(Node that) {
		if (inBounds(that)) {
			if (!is Tree.LetClause that) {
				node = that;
			}
			super.visitAny(that);
		}
		//otherwise, as a performance optimization
		//don't go any further down this branch
	}
	
	shared actual void visit(Tree.ImportPath that) {
		if (inBounds(that)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.BinaryOperatorExpression that) {
		Term right = that.rightTerm else that;
		Term left = that.leftTerm else that;
		
		if (inBounds(left, right)) {
			node=that;
		}
		super.visit(that);
	}
	
	shared actual void visit(Tree.UnaryOperatorExpression that) {
		Term term = that.term else that;
		if (inBounds(that, term) || inBounds(term, that)) {
			node=that;
		}
		super.visit(that);
	}
	
	shared actual void visit(Tree.ParameterList that) {
		if (inBounds(that)) {
			node=that;
		}
		super.visit(that);
	}
	
	shared actual void visit(Tree.TypeParameterList that) {
		if (inBounds(that)) {
			node=that;
		}
		super.visit(that);
	}
	
	shared actual void visit(Tree.ArgumentList that) {
		if (inBounds(that)) {
			node=that;
		}
		super.visit(that);
	}
	
	shared actual void visit(Tree.TypeArgumentList that) {
		if (inBounds(that)) {
			node=that;
		}
		super.visit(that);
	}
	
	shared actual void visit(Tree.QualifiedMemberOrTypeExpression that) {
		if (inBounds(that.memberOperator, that.identifier)) {
			node=that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.StaticMemberOrTypeExpression that) {
		if (inBounds(that.identifier)) {
			node = that;
			//Note: we can't be sure that this is "really"
			//      an EXPRESSION!
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.SimpleType that) {
		if (inBounds(that.identifier)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.ImportMemberOrType that) {
		if (inBounds(that.identifier) || inBounds(that.\ialias)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.Declaration that) {
		if (inBounds(that.identifier)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.InitializerParameter that) {
		if (inBounds(that.identifier)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.NamedArgument that) {
		if (inBounds(that.identifier)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
	shared actual void visit(Tree.DocLink that) {
		if (inBounds(that)) {
			node = that;
		}
		else {
			super.visit(that);
		}
	}
	
}