;;;;EXPLICIT-CONTROL EVALUATOR FROM SECTION 5.4 OF
;;;; STRUCTURE AND INTERPRETATION OF COMPUTER PROGRAMS

;;;;Matches code in ch5.scm

;;; To use it
;;; -- load "load-eceval.scm", which loads this file and the
;;;    support it needs (including the register-machine simulator)

;;; -- To initialize and start the machine, do

;: (define the-global-environment (setup-environment))

;: (start eceval)

;; To restart, can do just
;: (start eceval)
;;;;;;;;;;


;;**NB. To [not] monitor stack operations, comment in/[out] the line after
;; print-result in the machine controller below
;;**Also choose the desired make-stack version in regsim.scm

(define eceval-operations                                           ; <==== 5.4: The Explicit-Control Evaluator
  (list
   ;;primitive Scheme operations
   (list 'read read)                                                ; Operations
                                                                        ; "To clarify the presentation... include as primitive[s]...
   ;;operations in syntax.scm                                           ; "the syntax procedures given in section 4.1.2...
   (list 'self-evaluating? self-evaluating?)
   (list 'quoted? quoted?)
   (list 'text-of-quotation text-of-quotation)
   (list 'variable? variable?)
   (list 'assignment? assignment?)
   (list 'assignment-variable assignment-variable)
   (list 'assignment-value assignment-value)
   (list 'definition? definition?)
   (list 'definition-variable definition-variable)
   (list 'definition-value definition-value)
   (list 'lambda? lambda?)
   (list 'lambda-parameters lambda-parameters)
   (list 'lambda-body lambda-body)
   (list 'if? if?)
   (list 'if-predicate if-predicate)
   (list 'if-consequent if-consequent)
   (list 'if-alternative if-alternative)
   (list 'begin? begin?)
   (list 'begin-actions begin-actions)
   (list 'last-exp? last-exp?)
   (list 'first-exp first-exp)
   (list 'rest-exps rest-exps)
   (list 'application? application?)
   (list 'operator operator)
   (list 'operands operands)
   (list 'no-operands? no-operands?)
   (list 'first-operand first-operand)
   (list 'rest-operands rest-operands)

   ;;operations in eceval-support.scm                                   ; "and the procedures for representing environments and other
   (list 'true? true?)                                                  ; "run-time data given in sections 4.1.3 and 4.1.4"
   (list 'make-procedure make-procedure)                                ; [i.e., a full "assembly-code" implementation would be thousands of lines long...]
   (list 'compound-procedure? compound-procedure?)
   (list 'procedure-parameters procedure-parameters)
   (list 'procedure-body procedure-body)
   (list 'procedure-environment procedure-environment)
   (list 'extend-environment extend-environment)
   (list 'lookup-variable-value lookup-variable-value)
   (list 'set-variable-value! set-variable-value!)
   (list 'define-variable! define-variable!)
   (list 'primitive-procedure? primitive-procedure?)
   (list 'apply-primitive-procedure apply-primitive-procedure)
   (list 'prompt-for-input prompt-for-input)
   (list 'announce-output announce-output)
   (list 'user-print user-print)
   (list 'empty-arglist empty-arglist)
   (list 'adjoin-arg adjoin-arg)
   (list 'last-operand? last-operand?)
   (list 'no-more-exps? no-more-exps?)	;for non-tail-recursive machine
   (list 'get-global-environment get-global-environment))
   )

(define eceval                                                      ; Registers
  (make-machine                                                         ; the eceval register machine includes a stack and 7 registers.
   '(expr env val proc argl continue unev)                              ; expr = expression to be evaluated; env = environment for evaluation
   eceval-operations                                                    ; val = value resulting from evaluating expr in env
  '(                                                                    ; continue is used to implement recursion (remember 5.1.4?) - to evaluate subexpressions
;;SECTION 5.4.4                                                         ; proc, argl, and unev are used in evaluating combinations.
read-eval-print-loop
  (perform (op initialize-stack))
  (perform
   (op prompt-for-input) (const ";;; EC-Eval input:"))
  (assign expr (op read))
  (assign env (op get-global-environment))
  (assign continue (label print-result))
  (goto (label eval-dispatch))
print-result
;;**following instruction optional -- if use it, need monitored stack
  (perform (op print-stack-statistics))
  (perform
   (op announce-output) (const ";;; EC-Eval value:"))
  (perform (op user-print) (reg val))
  (goto (label read-eval-print-loop))

unknown-expression-type
  (assign val (const unknown-expression-type-error))
  (goto (label signal-error))

unknown-procedure-type
  (restore continue)
  (assign val (const unknown-procedure-type-error))
  (goto (label signal-error))

signal-error
  (perform (op user-print) (reg val))
  (goto (label read-eval-print-loop))

;;SECTION 5.4.1                                                     ; <==== 5.4.1 The Core of the Explicit-Control Evaluator
eval-dispatch                                                           ; corresponds to (eval) in ch4-mceval.scm (p. 365)
  (test (op self-evaluating?) (reg expr))                                   ; evaluate:
  (branch (label ev-self-eval))                                             ; the expression specified by expr,
  (test (op variable?) (reg expr))                                          ; in the environment specified by env
  (branch (label ev-variable))                                              
  (test (op quoted?) (reg expr))                                            ; result: val = value of the expression,
  (branch (label ev-quoted))                                                ; and the controller will go to the entry point stored in continue
  (test (op assignment?) (reg expr))
  (branch (label ev-assignment))
  (test (op definition?) (reg expr))
  (branch (label ev-definition))
  (test (op if?) (reg expr))
  (branch (label ev-if))
  (test (op lambda?) (reg expr))
  (branch (label ev-lambda))
  (test (op begin?) (reg expr))
  (branch (label ev-begin))
  (test (op application?) (reg expr))
  (branch (label ev-application))
  (goto (label unknown-expression-type))                                ; Footnote 20 p. 549 - a Lisp ASIC (shudder) would implement 
                                                                            ; a more efficient (dispatch-on-type) assembly instruction
ev-self-eval                                                        ; Evaluating simple expressions
  (assign val (reg expr))
  (goto (reg continue))
ev-variable
  (assign val (op lookup-variable-value) (reg expr) (reg env))
  (goto (reg continue))
ev-quoted
  (assign val (op text-of-quotation) (reg expr))
  (goto (reg continue))
ev-lambda
  (assign unev (op lambda-parameters) (reg expr))
  (assign expr (op lambda-body) (reg expr))
  (assign val (op make-procedure)
              (reg unev) (reg expr) (reg env))
  (goto (reg continue))

ev-application
  (save continue)
  (save env)
  (assign unev (op operands) (reg expr))
  (save unev)
  (assign expr (op operator) (reg expr))
  (assign continue (label ev-appl-did-operator))
  (goto (label eval-dispatch))
ev-appl-did-operator
  (restore unev)
  (restore env)
  (assign argl (op empty-arglist))
  (assign proc (reg val))
  (test (op no-operands?) (reg unev))
  (branch (label apply-dispatch))
  (save proc)
ev-appl-operand-loop
  (save argl)
  (assign expr (op first-operand) (reg unev))
  (test (op last-operand?) (reg unev))
  (branch (label ev-appl-last-arg))
  (save env)
  (save unev)
  (assign continue (label ev-appl-accumulate-arg))
  (goto (label eval-dispatch))
ev-appl-accumulate-arg
  (restore unev)
  (restore env)
  (restore argl)
  (assign argl (op adjoin-arg) (reg val) (reg argl))
  (assign unev (op rest-operands) (reg unev))
  (goto (label ev-appl-operand-loop))
ev-appl-last-arg
  (assign continue (label ev-appl-accum-last-arg))
  (goto (label eval-dispatch))
ev-appl-accum-last-arg
  (restore argl)
  (assign argl (op adjoin-arg) (reg val) (reg argl))
  (restore proc)
  (goto (label apply-dispatch))
apply-dispatch
  (test (op primitive-procedure?) (reg proc))
  (branch (label primitive-apply))
  (test (op compound-procedure?) (reg proc))  
  (branch (label compound-apply))
  (goto (label unknown-procedure-type))

primitive-apply
  (assign val (op apply-primitive-procedure)
              (reg proc)
              (reg argl))
  (restore continue)
  (goto (reg continue))

compound-apply
  (assign unev (op procedure-parameters) (reg proc))
  (assign env (op procedure-environment) (reg proc))
  (assign env (op extend-environment)
              (reg unev) (reg argl) (reg env))
  (assign unev (op procedure-body) (reg proc))
  (goto (label ev-sequence))

;;;SECTION 5.4.2
ev-begin
  (assign unev (op begin-actions) (reg expr))
  (save continue)
  (goto (label ev-sequence))

ev-sequence
  (assign expr (op first-exp) (reg unev))
  (test (op last-exp?) (reg unev))
  (branch (label ev-sequence-last-exp))
  (save unev)
  (save env)
  (assign continue (label ev-sequence-continue))
  (goto (label eval-dispatch))
ev-sequence-continue
  (restore env)
  (restore unev)
  (assign unev (op rest-exps) (reg unev))
  (goto (label ev-sequence))
ev-sequence-last-exp
  (restore continue)
  (goto (label eval-dispatch))

;;;SECTION 5.4.3

ev-if
  (save expr)
  (save env)
  (save continue)
  (assign continue (label ev-if-decide))
  (assign expr (op if-predicate) (reg expr))
  (goto (label eval-dispatch))
ev-if-decide
  (restore continue)
  (restore env)
  (restore expr)
  (test (op true?) (reg val))
  (branch (label ev-if-consequent))
ev-if-alternative
  (assign expr (op if-alternative) (reg expr))
  (goto (label eval-dispatch))
ev-if-consequent
  (assign expr (op if-consequent) (reg expr))
  (goto (label eval-dispatch))

ev-assignment
  (assign unev (op assignment-variable) (reg expr))
  (save unev)
  (assign expr (op assignment-value) (reg expr))
  (save env)
  (save continue)
  (assign continue (label ev-assignment-1))
  (goto (label eval-dispatch))
ev-assignment-1
  (restore continue)
  (restore env)
  (restore unev)
  (perform
   (op set-variable-value!) (reg unev) (reg val) (reg env))
  (assign val (const ok))
  (goto (reg continue))

ev-definition
  (assign unev (op definition-variable) (reg expr))
  (save unev)
  (assign expr (op definition-value) (reg expr))
  (save env)
  (save continue)
  (assign continue (label ev-definition-1))
  (goto (label eval-dispatch))
ev-definition-1
  (restore continue)
  (restore env)
  (restore unev)
  (perform
   (op define-variable!) (reg unev) (reg val) (reg env))
  (assign val (const ok))
  (goto (reg continue))
   )))

'(EXPLICIT CONTROL EVALUATOR LOADED)