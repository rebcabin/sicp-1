;;;;COMPILER FROM SECTION 5.5 OF
;;;; STRUCTURE AND INTERPRETATION OF COMPUTER PROGRAMS

;;;;Matches code in ch5.scm

;;;;This file can be loaded into Scheme as a whole.
;;;;**NOTE**This file loads the metacircular evaluator's syntax procedures
;;;;  from section 4.1.2
;;;;  You may need to change the (load ...) exprression to work in your
;;;;  version of Scheme.

;;;;Then you can compile Scheme programs as shown in section 5.5.5

;;**implementation-dependent loading of syntax procedures
(load "ch5-syntax.scm")			;section 4.1.2 syntax procedures


;;;SECTION 5.5.1                                                ; <==== 5.5.1: Structure of the Compiler
                                                               
(define (compile expr target linkage)                               ; top-level dispatch, corresponding to (eval), (analyze), and eval-dispatch 
  (cond ((self-evaluating? expr)                                        ; again uses expression-syntax procedures from 4.1.2 
         (compile-self-evaluating expr target linkage))
        ((quoted? expr) (compile-quoted expr target linkage))       ; Targets and linkages, p. 571    
        ((variable? expr)                                               ; target = register in which compiled code returns value of expression
         (compile-variable expr target linkage))                        ; linkage = describes how to proceed after compiled code has executed
        ((assignment? expr)                                                 ; "next": continue at next instruction in sequence
         (compile-assignment expr target linkage))                          ; "return": return from procedure being compiled
        ((definition? expr)                                                 ; <label>: jump to a named entry point
         (compile-definition expr target linkage))
        ((if? expr) (compile-if expr target linkage))
        ((lambda? expr) (compile-lambda expr target linkage))       ; "code generators"
        ((begin? expr)
         (compile-sequence (begin-actions expr)
                           target
                           linkage))
        ((cond? expr) (compile (cond->if expr) target linkage))
        ((application? expr)
         (compile-application expr target linkage))
        (else
         (error "Unknown exprression type -- COMPILE" expr))))


(define (make-instruction-sequence needs modifies statements)       ; p. 573: An instruction sequence will contain three pieces of information:
  (list needs modifies statements))                                     ; needs: registers [to be READ] that must be initialized before instructions are executed
                                                                        ; modifies: registers [to be WRITTEN] whose values are modified by instructions
(define (empty-instruction-sequence)                                    ; statements: the actual instructions
  (make-instruction-sequence '() '() '()))                              ; the first 2 are used by (append-instruction-sequences) and (preserving) - 5.5.4 code below


;;;SECTION 5.5.2                                            ; <==== 5.5.2: Compiling Expressions

;;;linkage code                                                 ; Compiling linkage code

(define (compile-linkage linkage)                                   ; "In general, the output of each code generator will end" with this.
  (cond ((eq? linkage 'return)
         (make-instruction-sequence '(continue) '()                     ; return: needs continue, modifies none.
          '((goto (reg continue)))))
        ((eq? linkage 'next)
         (empty-instruction-sequence))                                  ; next: do nothing!
        (else
         (make-instruction-sequence '() '()
          `((goto (label ,linkage)))))))                                ; else: goto linkage. for backquote syntax, see Footnote 36.

(define (end-with-linkage linkage instruction-sequence)             ; append linkage to an instruction sequence (not ALWAYS done! see below)
  (preserving '(continue)                                               ; preserve continue, if ...
   instruction-sequence                                                 ; the given instruction sequence modifies it and...
   (compile-linkage linkage)))                                          ; the linkage code needs it (return linkage)


;;;simple exprressions                                          ; Compiling simple expressions

(define (compile-self-evaluating expr target linkage)
  (end-with-linkage linkage
   (make-instruction-sequence '() (list target)                     ; Assign the required value to the target register [argument]...
    `((assign ,target (const ,expr))))))                                ; [don't want a literal "target" INSIDE the quote!]

(define (compile-quoted expr target linkage)
  (end-with-linkage linkage                                         ; and then proceed as specified by the linkage descriptor [argument].
   (make-instruction-sequence '() (list target)                     ; All these instructions will modify the target register...
    `((assign ,target (const ,(text-of-quotation expr)))))))            ; [the compiler can bake in quotation text instead of using reg val!]

(define (compile-variable expr target linkage)
  (end-with-linkage linkage
   (make-instruction-sequence '(env) (list target)                  ; and the one that looks up a variable needs the env register.
    `((assign ,target
              (op lookup-variable-value)
              (const ,expr)                                             ; [the compiler can bake in variable names instead of using reg val!]
              (reg env))))))

(define (compile-assignment expr target linkage)                    ; Assignments and definitions are handled much as they are in the interpreter.
  (let ((var (assignment-variable expr))
        (get-value-code                                                 ; generate code that computes the value to be assigned to the variable,
         (compile (assignment-value expr) 'val 'next)))                     ; [with target val and linkage next for appending]
    (end-with-linkage linkage
     (preserving '(env)                                                     ; [save env for set! to modify - since get-value-code might trash it]
      get-value-code                                                    ; and append to it...
      (make-instruction-sequence '(env val) (list target)               ; a two-instruction sequence...
       `((perform (op set-variable-value!)                              ; that actually sets/defines the variable...
                  (const ,var)
                  (reg val)                                                 ; [using the result val from get-value-code]
                  (reg env))
         (assign ,target (const ok))))))))                              ; and returns 'ok in the target register.

(define (compile-definition expr target linkage)
  (let ((var (definition-variable expr))
        (get-value-code
         (compile (definition-value expr) 'val 'next)))
    (end-with-linkage linkage
     (preserving '(env)
      get-value-code
      (make-instruction-sequence '(env val) (list target)
       `((perform (op define-variable!)                                 ; <--- the only difference with (compile-assignment).        
                  (const ,var)
                  (reg val)
                  (reg env))
         (assign ,target (const ok))))))))


;;;conditional exprressions                                     ; Compiling conditional expressions
                                                                    
;;;labels (from footnote)                                           ; Footnote 37 p. 578: generate labels that are unique within the object code
(define label-counter 0)                                                ; cf. unique query variable names - pp. 477, 486 Secs 4.4.4.4 and 4.4.4.7
                                                                    ; code skeleton p. 577
(define (new-label-number)                                          ;  <compiled predicate, target val, linkage next>
  (set! label-counter (+ 1 label-counter))                          ;  (test (op false?) (reg val))
  label-counter)                                                    ;  (branch (label false-branch))
                                                                    ; true-branch
(define (make-label name)                                           ;  <compiled consequent with given target and given linkage or after-if> [need after-if if given linkage = next]
  (string->symbol                                                   ; false-branch
    (string-append (symbol->string name)                            ;  <compilation of alternative with given target and linkage>
                   (number->string (new-label-number)))))           ; after-if
;; end of footnote

(define (compile-if expr target linkage)
  (let ((t-branch (make-label 'true-branch))
        (f-branch (make-label 'false-branch))                    
        (after-if (make-label 'after-if)))
    (let ((consequent-linkage                                       ; if linkage = return or label, true uses it directly
           (if (eq? linkage 'next) after-if linkage)))                  ; but for linkage = next, jump around false code to after-if
      (let ((p-code (compile (if-predicate expr) 'val 'next))       ; compile the predicate, consequent, and alternative
            (c-code
             (compile
              (if-consequent expr) target consequent-linkage))
            (a-code
             (compile (if-alternative expr) target linkage)))
        (preserving '(env continue)                                 ; env might be needed by c-code/a-code, continue by linkage
         p-code
         (append-instruction-sequences
          (make-instruction-sequence '(val) '()
           `((test (op false?) (reg val))                           ; test the predicate result, with newly-inserted labels
             (branch (label ,f-branch))))
          (parallel-instruction-sequences                           ; special combiner from 5.5.4: instructions in parallel
           (append-instruction-sequences t-branch c-code)               ; (no need for preserving between them)
           (append-instruction-sequences f-branch a-code))
          after-if))))))

;;; sequences                                                   ; Compiling sequences

(define (compile-sequence seq target linkage)                       ; parallels ev-sequence
  (if (last-exp? seq)                                                   
      (compile (first-exp seq) target linkage)                          ; last expression with (final) linkage for the sequence
      (preserving '(env continue)                                           ; env needed for rest of seq, continue (possibly) for final linkage
       (compile (first-exp seq) target 'next)                           ; other expressions with linkage next (to rest of sequence)
       (compile-sequence (rest-exps seq) target linkage))))

;;;lambda exprressions                                          ; Compiling lambda expressions

(define (compile-lambda expr target linkage)                        ; code to construct procedure object; followed by code for procedure body    
  (let ((proc-entry (make-label 'entry))                                
        (after-lambda (make-label 'after-lambda)))                      ; hmm, generates label before it knows it's necessary...
    (let ((lambda-linkage                                               
           (if (eq? linkage 'next) after-lambda linkage)))              ; need to skip body if linkage is next (return or goto proceeds normally)
      (append-instruction-sequences                                     
       (tack-on-instruction-sequence                                    ; special combiner from 5.5.4 (2nd seq not executed)
        (end-with-linkage lambda-linkage                                
         (make-instruction-sequence '(env) (list target)                
          `((assign ,target                                             ; <construct procedure object and assign it to target register>
                    (op make-compiled-procedure)                            ; new op - Footnote 38 p. 580
                    (label ,proc-entry)                                     ; proc body entry point + current env (SAVED from point of definition) - p. 580
                    (reg env)))))                                       ; <lambda-linkage> - from (end-with-linkage)
        (compile-lambda-body expr proc-entry))                          ; <compiled body> - from (tack-on-instruction-sequence)
       after-lambda))))                                                 ; label after-lambda - from (append-instruction-sequences)

(define (compile-lambda-body expr proc-entry)                       ; code for body [since we're already here]
  (let ((formals (lambda-parameters expr)))                             ; ONLY invoked from (compile-lambda).
    (append-instruction-sequences
     (make-instruction-sequence '(env proc argl) '(env)
      `(,proc-entry                                                     ; label for entry point (for application)
        (assign env (op compiled-procedure-env) (reg proc))             ; the definition env of the procedure...
        (assign env
                (op extend-environment)                                     ; extended to include bindings of arguments
                (const ,formals)
                (reg argl)
                (reg env))))
     (compile-sequence (lambda-body expr) 'val 'return))))              ; the procedure body
                                                                        ; always end with return(val).

;;;SECTION 5.5.3                                            ; <==== 5.5.3: Compiling Combinations [i.e., procedure applications - p. 6!]       

;;;combinations

(define (compile-application expr target linkage)               ; "The essence of the compilation process is the compilation of procedure applications."
  (let ((proc-code (compile (operator expr) 'proc 'next))           ; <---- the only place where target != val in the compiler
        (operand-codes
         (map (lambda (operand) (compile operand 'val 'next))
              (operands expr))))
    (preserving '(env continue)                                         ; env needed for operands, continue for final linkage
     proc-code                                                      ; <compilation of operator, target proc, linkage next>
     (preserving '(proc continue)                                       ; proc needed for final application, continue for final linkage
      (construct-arglist operand-codes)                             ; <evaluate operands and construct argument list in argl>
      (compile-procedure-call target linkage)))))                   ; <compilation of procedure call with given target and linkage>

(define (construct-arglist operand-codes)                       ; ONLY invoked from (compile-application). "tricky, because of the special treatment of the first operand to be evaluated"
  (let ((operand-codes (reverse operand-codes)))                    ; build up argl using cons, so start with the last arg
    (if (null? operand-codes)                                       ; operand-codes = (reversed) list of compiled operands
        (make-instruction-sequence '() '(argl)                      
         '((assign argl (const ()))))                               ; no arguments, so argl = '(). handled as a special case, "rather than [always] waste an an instruction by initializing argl to the empty list"
        (let ((code-to-get-last-arg
               (append-instruction-sequences                        ; argl construction skeleton p. 582
                (car operand-codes)                                     ; <compilation of last operand, targeted to val>
                (make-instruction-sequence '(val) '(argl)
                 '((assign argl (op list) (reg val)))))))               ; (assign argl (op list) (reg val))
          (if (null? (cdr operand-codes))
              code-to-get-last-arg
              (preserving '(env)                                            ; preserve env for subsequent operand evaluations
               code-to-get-last-arg
               (code-to-get-rest-args                                   ; *<compilation of next operand, targeted to val>
                (cdr operand-codes))))))))                              ; **(assign argl (op cons) (reg val) (reg argl)) below

(define (code-to-get-rest-args operand-codes)                   ; ONLY invoked from (construct-arglist)
  (let ((code-for-next-arg
         (preserving '(argl)                                        ; operand code might trash argl!
          (car operand-codes)                                       ; * above
          (make-instruction-sequence '(val argl) '(argl)
           '((assign argl                                           ; ** above
              (op cons) (reg val) (reg argl)))))))
    (if (null? (cdr operand-codes))                                 ; if this is the last arg (in the reversed list)
        code-for-next-arg                                               ; then we are done!
        (preserving '(env)                                              ; otherwise, save the env...
         code-for-next-arg
         (code-to-get-rest-args (cdr operand-codes))))))                ; for evaluating the next operand.

;;;applying procedures                                          ; Applying procedures - cf. (apply) from 4.1.1 p. 366 or apply-dispatch from 5.4.1 p. 553
                                                                    ; precondition: proc = operator value, argl = operand values
(define (compile-procedure-call target linkage)
  (let ((primitive-branch (make-label 'primitive-branch))
        (compiled-branch (make-label 'compiled-branch))
        (after-call (make-label 'after-call)))
    (let ((compiled-linkage                                         ; cf. linkage for true-branch for compile-if
           (if (eq? linkage 'next) after-call linkage)))
      (append-instruction-sequences
       (make-instruction-sequence '(proc) '()                       ; skeleton p. 584
        `((test (op primitive-procedure?) (reg proc))               ; (test (op primitive-procedure?) (reg proc))
          (branch (label ,primitive-branch))))                      ; (branch (label ,primitive-branch))
       (parallel-instruction-sequences                                  ; special combiner like with if
        (append-instruction-sequences
         compiled-branch                                            ; compiled-branch [next-linkage skips primitive-branch]
         (compile-proc-appl target compiled-linkage))               ; <code to apply compiled procedure with given target and appropriate linkage>
        (append-instruction-sequences
         primitive-branch                                           ; primitive-branch
         (end-with-linkage linkage
          (make-instruction-sequence '(proc argl)
                                     (list target)
           `((assign ,target                                        ; (assign <target> (op apply-primitive-procedure) (reg proc) (reg argl))
                     (op apply-primitive-procedure)
                     (reg proc)
                     (reg argl)))))))                               ; <linkage> [argument - from (end-with-linkage)]
       after-call))))                                               ; after-call

;;;applying compiled procedures

(define (compile-proc-appl target linkage)
  (cond ((and (eq? target 'val) (not (eq? linkage 'return)))
         (make-instruction-sequence '(proc) all-regs
           `((assign continue (label ,linkage))
             (assign val (op compiled-procedure-entry)
                         (reg proc))
             (goto (reg val)))))
        ((and (not (eq? target 'val))
              (not (eq? linkage 'return)))
         (let ((proc-return (make-label 'proc-return)))
           (make-instruction-sequence '(proc) all-regs
            `((assign continue (label ,proc-return))
              (assign val (op compiled-procedure-entry)
                          (reg proc))
              (goto (reg val))
              ,proc-return
              (assign ,target (reg val))
              (goto (label ,linkage))))))
        ((and (eq? target 'val) (eq? linkage 'return))
         (make-instruction-sequence '(proc continue) all-regs
          '((assign val (op compiled-procedure-entry)
                        (reg proc))
            (goto (reg val)))))
        ((and (not (eq? target 'val)) (eq? linkage 'return))
         (error "return linkage, target not val -- COMPILE"
                target))))

;; footnote
(define all-regs '(env proc val argl continue))


;;;SECTION 5.5.4

(define (registers-needed s)
  (if (symbol? s) '() (car s)))

(define (registers-modified s)
  (if (symbol? s) '() (cadr s)))

(define (statements s)
  (if (symbol? s) (list s) (caddr s)))

(define (needs-register? seq reg)
  (memq reg (registers-needed seq)))

(define (modifies-register? seq reg)
  (memq reg (registers-modified seq)))


(define (append-instruction-sequences . seqs)                       ; previewed in 5.5.1 on p. 572: append all, with register analysis to simplify (preserving)
  (define (append-2-sequences seq1 seq2)
    (make-instruction-sequence                                          ; overview of register metadata: p. 573
     (list-union (registers-needed seq1)
                 (list-difference (registers-needed seq2)
                                  (registers-modified seq1)))
     (list-union (registers-modified seq1)
                 (registers-modified seq2))
     (append (statements seq1) (statements seq2))))
  (define (append-seq-list seqs)
    (if (null? seqs)
        (empty-instruction-sequence)
        (append-2-sequences (car seqs)
                            (append-seq-list (cdr seqs)))))
  (append-seq-list seqs))

(define (list-union s1 s2)
  (cond ((null? s1) s2)
        ((memq (car s1) s2) (list-union (cdr s1) s2))
        (else (cons (car s1) (list-union (cdr s1) s2)))))

(define (list-difference s1 s2)
  (cond ((null? s1) '())
        ((memq (car s1) s2) (list-difference (cdr s1) s2))
        (else (cons (car s1)
                    (list-difference (cdr s1) s2)))))

(define (preserving regs seq1 seq2)                                 ; previewed in 5.5.1 on p. 572: returns ((wrap seq1) seq2), where 
  (if (null? regs)                                                      ; (wrap seq1) INTELLIGENTLY wraps seq1 with push/pop pairs for regs 
      (append-instruction-sequences seq1 seq2)
      (let ((first-reg (car regs)))
        (if (and (needs-register? seq2 first-reg)
                 (modifies-register? seq1 first-reg))
            (preserving (cdr regs)
             (make-instruction-sequence
              (list-union (list first-reg)
                          (registers-needed seq1))
              (list-difference (registers-modified seq1)
                               (list first-reg))
              (append `((save ,first-reg))                              ; ALL push/pops generated here! code generators don't worry about it.
                      (statements seq1)                                 
                      `((restore ,first-reg))))
             seq2)
            (preserving (cdr regs) seq1 seq2)))))

(define (tack-on-instruction-sequence seq body-seq)
  (make-instruction-sequence
   (registers-needed seq)
   (registers-modified seq)
   (append (statements seq) (statements body-seq))))

(define (parallel-instruction-sequences seq1 seq2)
  (make-instruction-sequence
   (list-union (registers-needed seq1)
               (registers-needed seq2))
   (list-union (registers-modified seq1)
               (registers-modified seq2))
   (append (statements seq1) (statements seq2))))

'(COMPILER LOADED)
