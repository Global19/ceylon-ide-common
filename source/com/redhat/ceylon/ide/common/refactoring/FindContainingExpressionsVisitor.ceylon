import ceylon.collection {
    ArrayList
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree,
    Visitor
}

import java.lang {
    ObjectArray
}

shared class FindContainingExpressionsVisitor(Integer offset) extends Visitor() {

    value myElements = ArrayList<Tree.Term>();
    
    shared ObjectArray<Tree.Term> elements => ObjectArray.with(myElements);
    
    shared actual void visit(Tree.Term that) {
        super.visit(that);
        
        if (!is Tree.Expression that,
                exists start = that.startIndex?.intValue(),
                exists end = that.endIndex?.intValue(),
                start <= offset && end >= offset) {
            myElements.add(that);
        }
    }
}