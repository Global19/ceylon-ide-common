import ceylon.collection {
    MutableList
}
import ceylon.interop.java {
    CeylonIterable
}
import com.redhat.ceylon.compiler.typechecker.tree {
    Node
}
import com.redhat.ceylon.ide.common.typechecker {
    LocalAnalysisResult
}
import com.redhat.ceylon.ide.common.util {
    Indents
}
import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    DeclarationWithProximity,
    Value
}

shared interface ControlStructureCompletionProposal<IdeComponent,IdeArtifact,CompletionResult,Document>
        given IdeComponent satisfies LocalAnalysisResult<Document,IdeArtifact>
        given IdeArtifact satisfies Object {
    
    shared formal CompletionResult newControlStructureCompletionProposal(Integer offset, String prefix,
        String desc, String text, Declaration dec, IdeComponent cpc);
    
    shared void addForProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d) {
        
        if (is Value d) {
            value td = d;
            if (exists t = td.type, d.unit.isIterableType(td.type)) {
                value name = d.name;
                value elemName = if (name.size == 1)
                then "element"
                else if (name.endsWith("s"))
                    then name.spanTo(name.size - 2)
                    else name.spanTo(0);
                
                value unit = cpc.lastCompilationUnit.unit;
                value desc = "for (" + elemName + " in " + getDescriptionFor(d, unit) + ")";
                value text = "for (" + elemName + " in " + getTextFor(d, unit) + ") {}";
                
                result.add(newControlStructureCompletionProposal(offset, prefix, desc, text, d, cpc));
            }
        }
    }
    
    shared void addIfExistsProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d) {
        
        if (!dwp.unimported) {
            if (is Value v = d) {
                if (exists type = v.type, d.unit.isOptionalType(type), !v.variable) {
                    value unit = cpc.lastCompilationUnit.unit;
                    value desc = "if (exists " + getDescriptionFor(d, unit) + ")";
                    value text = "if (exists " + getTextFor(d, unit) + ") {}";
                    
                    result.add(newControlStructureCompletionProposal(offset, prefix, desc, text, d, cpc));
                }
            }
        }
    }
    
    shared void addAssertExistsProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d) {
        
        if (!dwp.unimported) {
            if (is Value d) {
                value v = d;
                if (v.type exists, d.unit.isOptionalType(v.type), !v.variable) {
                    value unit = cpc.lastCompilationUnit.unit;
                    result.add(newControlStructureCompletionProposal(offset, prefix,
                            "assert (exists " + getDescriptionFor(d, unit) + ")",
                            "assert (exists " + getTextFor(d, unit) + ");", d, cpc));
                }
            }
        }
    }
    
    shared void addIfNonemptyProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d) {
        
        if (!dwp.unimported) {
            if (is Value v = d) {
                if (exists type = v.type, d.unit.isPossiblyEmptyType(type), !v.variable) {
                    value unit = cpc.lastCompilationUnit.unit;
                    value desc = "if (nonempty " + getDescriptionFor(d, unit) + ")";
                    value text = "if (nonempty " + getTextFor(d, unit) + ") {}";
                    result.add(newControlStructureCompletionProposal(offset, prefix, desc, text, d, cpc));
                }
            }
        }
    }
    
    shared void addAssertNonemptyProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d) {
        
        if (!dwp.unimported) {
            if (is Value d) {
                value v = d;
                if (v.type exists, d.unit.isPossiblyEmptyType(v.type), !v.variable) {
                    value unit = cpc.lastCompilationUnit.unit;
                    result.add(newControlStructureCompletionProposal(offset, prefix,
                            "assert (nonempty " + getDescriptionFor(d, unit) + ")",
                            "assert (nonempty " + getTextFor(d, unit) + ");",
                            d, cpc));
                }
            }
        }
    }
    
    shared void addTryProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d) {
        
        if (!dwp.unimported) {
            if (is Value d) {
                value v = d;
                if (exists type = v.type, v.type.declaration.inherits(d.unit.obtainableDeclaration), !v.variable) {
                    value unit = cpc.lastCompilationUnit.unit;
                    value desc = "try (" + getDescriptionFor(d, unit) + ")";
                    value text = "try (" + getTextFor(d, unit) + ") {}";
                    
                    result.add(newControlStructureCompletionProposal(offset, prefix, desc, text, d, cpc));
                }
            }
        }
    }
    
    shared void addSwitchProposal(Integer offset, String prefix, IdeComponent cpc, MutableList<CompletionResult> result,
        DeclarationWithProximity dwp, Declaration d, Node node, Indents<Document> indents) {
        
        if (!dwp.unimported) {
            if (is Value v = d) {
                if (exists type = v.type, exists caseTypes = v.type.caseTypes, !v.variable) {
                    value body = StringBuilder();
                    value indent = indents.getIndent(node, cpc.document);
                    value unit = node.unit;
                    for (pt in CeylonIterable(caseTypes)) {
                        body.append(indent).append("case (");
                        value ctd = pt.declaration;
                        if (ctd.anonymous) {
                            if (!ctd.toplevel) {
                                body.append(type.declaration.getName(unit)).append(".");
                            }
                            body.append(ctd.getName(unit));
                        } else {
                            body.append("is ").append(pt.asSourceCodeString(unit));
                        }
                        body.append(") {}").append(indents.getDefaultLineDelimiter(cpc.document));
                    }
                    body.append(indent);
                    value u = cpc.lastCompilationUnit.unit;
                    value desc = "switch (" + getDescriptionFor(d, u) + ")";
                    value text = "switch (" + getTextFor(d, u) + ")"
                            + indents.getDefaultLineDelimiter(cpc.document) + body.string;
                    result.add(newControlStructureCompletionProposal(offset, prefix, desc, text, d, cpc));
                }
            }
        }
    }
}
