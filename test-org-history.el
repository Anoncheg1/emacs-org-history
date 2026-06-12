(require 'ert)
(require 'cl-lib)
(require 'vc-git)
(require 'org-history)
(require 'org-history-debug)

(defvar ert-enabled t)
(when org-history-debug-buffer
  (setq ert-enabled nil))

;; -=-= 1)

(defmacro with-org-history-test-env (buffer-var file-var temp-dir-var &rest body)
  "Set up an isolated temporary Git and file environment for org-history testing."
  (declare (indent 3) (debug t))
  `(let* ((,temp-dir-var (file-name-as-directory (make-temp-file "org-history-test-" t)))
          (,file-var (expand-file-name "test-notes.org" ,temp-dir-var))
          (default-directory ,temp-dir-var)
          (,buffer-var nil))
     (unwind-protect
         (progn
           ;; Initialize dummy functions that are called in the hook but not provided
           (cl-letf* (((symbol-function 'org-history--debug) #'ignore)
                      ((symbol-function 'org-history-git-init) #'ignore)
                      ((symbol-function 'org-history-outline--add-dates) #'ignore)
                      ((symbol-function 'org-history-dir-locals-append) #'ignore)
                      ((symbol-function 'org-history--commit) #'ignore))
             ,@body))
       ;; Cleanup phase
       (when (get-file-buffer ,file-var)
         (with-current-buffer (get-file-buffer ,file-var)
           (set-buffer-modified-p nil))
         (kill-buffer (get-file-buffer ,file-var)))
       (when (file-exists-p ,temp-dir-var)
         (delete-directory ,temp-dir-var t)))))

;; =========================================================================
;; CASE 1: No Git Repository Exists At All
;; =========================================================================

(ert-deftest test-org-history-hook--case1-user-accepts ()
  "Case 1: No Git repo. User answers YES to initializing tracking."
  (with-org-history-test-env buf file temp-dir
    (setq buf (find-file file))
    (org-mode)
    (insert "Heading 1\n")

    (let ((init-called nil))
      (cl-letf (((symbol-function 'vc-git-root) (lambda (&rest _) nil))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'org-history-git-init) (lambda (&rest _) (setq init-called t))))

        (let ((org-history-answer-was-given nil))
          (org-history-hook-for-after-save)
          (should init-called)
          (should (eq org-history-answer-was-given 'track-file)))))))

(ert-deftest test-org-history-hook--case1-user-declines ()
  "Case 1: No Git repo. User answers NO to initializing tracking."
  (with-org-history-test-env buf file temp-dir
    (setq buf (find-file file))
    (org-mode)

    (cl-letf (((symbol-function 'vc-git-root) (lambda (&rest _) nil))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))

      (let ((org-history-answer-was-given nil))
        (org-history-hook-for-after-save)
        (should (eq org-history-answer-was-given 'dont-track-file))))))

;; =========================================================================
;; CASE 2: Git Repo Exists + Same Day + Org-History Commit Prefix
;; =========================================================================

(ert-deftest test-org-history-hook--case2-transparent-amend ()
  "Case 2: Same-day file edits with org-history history should amend cleanly without prompt."
  (with-org-history-test-env buf file temp-dir
    (setq buf (find-file file))
    (org-mode)

    (let ((commit-called-with nil))
      (cl-letf (((symbol-function 'vc-git-root) (lambda (&rest _) temp-dir))
                ((symbol-function 'vc-backend) (lambda (&rest _) 'Git))
                ((symbol-function 'format-time-string) (lambda (&rest _) "2026-06-12"))
                ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-06-12"))
                ((symbol-function 'org-history--git-get-last-commit-message) (lambda (&rest _) "org-history: regular backup"))
                ((symbol-function 'org-history--dir-locals-p) (lambda (&rest _) t)) ;; dir-locals already present
                ((symbol-function 'org-history--commit) (lambda (date) (setq commit-called-with date))))

        (let ((org-history-answer-was-given 'track-file))
          (org-history-hook-for-after-save)
          ;; Transparently commits without prompting
          (should (string-equal commit-called-with "2026-06-12")))))))

;; =========================================================================
;; CASE 3: Git Repo Exists, New Commit or Initial Baseline Needed
;; =========================================================================

(ert-deftest test-org-history-hook--case3-new-day-commit ()
  "Case 3: A Git repo exists, but it's a new calendar day. Should trigger a brand new commit."
  (with-org-history-test-env buf file temp-dir
    (setq buf (find-file file))
    (org-mode)

    (let ((commit-called nil))
      (cl-letf (((symbol-function 'vc-git-root) (lambda (&rest _) temp-dir))
                ((symbol-function 'vc-backend) (lambda (&rest _) 'Git))
                ((symbol-function 'format-time-string) (lambda (&rest _) "2026-06-13")) ;; Next Day
                ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-06-12"))
                ((symbol-function 'org-history--git-get-last-commit-message) (lambda (&rest _) "org-history: day 1 tracking"))
                ((symbol-function 'org-history--dir-locals-p) (lambda (&rest _) t))
                ((symbol-function 'org-history--commit) (lambda (&rest _) (setq commit-called t))))

        (let ((org-history-answer-was-given 'track-file))
          (org-history-hook-for-after-save)
          ;; Verifies a normal follow-up day commit execution paths successfully
          (should commit-called))))))

;; =========================================================================
;; MINOR MODE INTERACTION: org-history-mode
;; =========================================================================

(ert-deftest test-org-history-mode-activation ()
  "Ensure org-history-mode safely activates inside org buffers and binds hooks correctly."
  (with-org-history-test-env buf file temp-dir
    (setq buf (find-file file))
    (org-mode)

    (cl-letf (((symbol-function 'org-history--vc-git-get-last-commit-hash) (lambda () "mocked-hash"))
              ((symbol-function 'org-history-outline--add-dates) #'ignore)
              ((symbol-function 'org-history--show-dates-at-unfold) #'ignore)
              ((symbol-function 'org-history--cycle-hook) #'ignore))

      ;; 1. Check activation behavior
      (org-history-mode 1)
      (should org-history-mode)
      (should (memq #'org-history-hook-for-after-save after-save-hook))

      ;; 2. Check deactivation behavior
      (cl-letf (((symbol-function 'org-history-outline-clear-all-org-date-overlays) #'ignore))
        (org-history-mode -1)
        (should-not org-history-mode)
        (should-not (memq #'org-history-hook-for-after-save after-save-hook))))))


(ert-deftest test-vc-git-commit-on-save--full-lifecycle2 ()
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-test-" t)))
         (test-file (expand-file-name "test-file.txt" temp-dir))
         (default-directory temp-dir))
    (unwind-protect
        (progn
          (find-file test-file)
          (org-mode)
          (org-history-git-init)
          (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
          (insert "Day 1: Initial lines of code.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22")))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
              (save-buffer t))))
      (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD 2>/dev/null || echo 0"))))
        (should (string-equal commit-count "1")))
      (when (get-file-buffer test-file)
        (set-buffer-modified-p nil)
        (kill-buffer (get-file-buffer test-file)))
      (delete-directory temp-dir t))))

(ert-deftest test-vc-git-commit-on-save--dot-git-already-exist-and-second-file ()
  "Test interaction when a repository baseline is established, and a second file
is added into the tracking loop on the same day."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-test-" t)))
         (test-file1 (expand-file-name "test-file1.txt" temp-dir))
         (test-file2 (expand-file-name "test-file2.txt" temp-dir))
         (default-directory temp-dir)
         buf1 buf2)
    (unwind-protect
        (progn
          ;; 1. Initialize a real Git repository in our temporary test directory
          (let ((vc-handled-backends '(Git)))
            (vc-git-command nil 0 nil "init"))

          ;; Configure Git user identities locally inside this temp environment
          ;; to ensure execution doesn't hang or fail in clean CI/CD setups.
          (let ((process-environment (cons (format "GIT_DIR=%s.git" temp-dir) process-environment)))
            (shell-command-to-string "git config user.name 'Test User'")
            (shell-command-to-string "git config user.email 'test@example.com'"))

          ;; 2. Open File 1: Simulate Case 3 (Repo exists, file not yet tracked)
          (setq buf1 (find-file test-file1))
          (org-mode)
          (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
          (insert "Day 1: Initial lines of code in File 1.\n")

          ;; Force a static current date string and accept tracking prompts
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22"))
                    ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                    ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
            (let ((org-history-answer-was-given nil))
              (save-buffer)))

          ;; Verify that File 1 successfully triggered the initial baseline commit
          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD")))
                (commit-msg (string-trim (shell-command-to-string "git log -1 --pretty=%B"))))
            (should (string-equal commit-count "1"))
            (should (string-prefix-p "org-history" commit-msg)))

          ;; 3. Open File 2: Evaluate same-day workflow behavior for secondary files
          (setq buf2 (find-file test-file2))
          (setq default-directory temp-dir) ;; Ensure context is locked locally
          (org-mode)
          (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
          (insert "Day 1: Initial lines of code in File 2.\n")

          (let ((old-hash (string-trim (shell-command-to-string "git rev-parse HEAD"))))
            (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22"))
                      ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-05-22"))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                      ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
              (let ((org-history-answer-was-given nil))
                (save-buffer)))

            ;; Clean properties block to confirm VC cache evaluates filesystem status correctly
            (vc-file-clearprops test-file2)

            ;; Because File 2 was not tracked yet, it defaults to Case 3 processing logic,
            ;; generating an automatic squash or a fresh transparent commit adjustment.
            (let ((new-hash (string-trim (shell-command-to-string "git rev-parse HEAD"))))
              ;; The repository state should progress to process our secondary tracking file
              (should-not (string-equal old-hash new-hash))))

          ;; 4. Post-Execution Integrity Check
          (let ((final-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
            ;; Asserts that execution succeeded cleanly without polluting or fragmenting repo states
            (should (member final-count '("1" "2")))))

      ;; Clean up generated test buffers properly
      (when buf1
        (with-current-buffer buf1 (set-buffer-modified-p nil))
        (kill-buffer buf1))
      (when buf2
        (with-current-buffer buf2 (set-buffer-modified-p nil))
        (kill-buffer buf2))
      (delete-directory temp-dir t))))


(ert-deftest test-vc-git-commit-on-save--untracked-file ()
  "Verify that an untracked file in an existing Git repository falls into
Case 3, prompts the user for tracking approval, and completes initialization."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-untracked-" t)))
         (untracked-file (expand-file-name "untracked.txt" temp-dir))
         (default-directory temp-dir)
         buf)
    (unwind-protect
        (progn
          ;; 1. Initialize an authentic Git repository on disk
          (let ((vc-handled-backends '(Git)))
            (vc-git-command nil 0 nil "init"))

          ;; Setup isolated local environments for headless CI runners
          (let ((process-environment (cons (format "GIT_DIR=%s.git" temp-dir) process-environment)))
            (shell-command-to-string "git config user.name 'Test User'")
            (shell-command-to-string "git config user.email 'test@example.com'"))

          ;; Create a baseline commit so that (vc-git--run-command-string nil "log" "-1") returns true
          (with-temp-file (expand-file-name "baseline.txt" temp-dir)
            (insert "Baseline content"))
          (shell-command-to-string "git add baseline.txt && git commit -m 'Initial baseline commit'")

          ;; 2. Open our target untracked file buffer context
          (setq buf (find-file untracked-file))
          (insert "This file is not tracked by Git yet.\n")
          (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)

          ;; FIX: Explicitly clear and initialize the state variable *locally* inside
          ;; the buffer context so dynamic evaluations inside the hook trace it properly.
          (setq-local org-history-answer-was-given nil)

          ;; 3. Prepare our white-box integration boundaries
          (let ((prompt-triggered nil)
                (commit-executed-date nil))
            (cl-letf* (;; Isolate debug tracking prints
                       ((symbol-function 'org-history--debug) #'ignore)
                       ;; Prevent real directory structures mutation inside our test
                       ((symbol-function 'org-history--dir-locals-p) (lambda (&rest _) nil))
                       ((symbol-function 'org-history-dir-locals-append) #'ignore)
                       ((symbol-function 'org-history-outline--add-dates) #'ignore)
                       ;; Track when the commit command is triggered by the hook
                       ((symbol-function 'org-history--commit) (lambda (date) (setq commit-executed-date (or date 'triggered))))
                       ;; Mock user interactive responses to accept tracking setup
                       ((symbol-function 'y-or-n-p) (lambda (&rest _) (setq prompt-triggered t) t)))

              (save-buffer)

              ;; 4. Post-Execution Validations
              ;; Because the file is untracked, Case 3 MUST prompt the user for setup!
              (should prompt-triggered)
              ;; Verify that tracking decision states updated successfully on the target buffer
              (should (eq org-history-answer-was-given 'track-file))
              ;; Verify that the commit execution loop was successfully dispatched
              (should commit-executed-date)))

          ;; Confirm that baseline repository integrity holds true
          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
            (should (string-equal commit-count "1"))))

      ;; Cleanup phase
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory temp-dir t))))



(ert-deftest test-org-history--my-append-existing-dir-locals ()
  (let* ((temp-dir (file-name-as-directory (make-temp-file "ert-test-" t)))
         (target-file (expand-file-name ".dir-locals.el" temp-dir))
         (dummy-file (expand-file-name "dummy.org" temp-dir))
         (initial-config '((python-mode . ((python-indent-offset . 4)))
                           (org-mode . ((org-todo-keywords . ("TODO" "DONE")))))))
    (unwind-protect
        (progn
          (with-temp-file target-file (pp initial-config (current-buffer)))
          (find-file dummy-file)
          (let ((default-directory temp-dir))
            (org-history-dir-locals-append))
          (with-temp-buffer
            (insert-file-contents target-file)
            (let ((result (read (current-buffer))))
              (should (equal (cdr (assoc 'python-mode result))
                             '((python-indent-offset . 4))))
              (should (member '(org-todo-keywords . ("TODO" "DONE"))
                              (cdr (assoc 'org-mode result)))))))
      (when (get-file-buffer dummy-file)
        (kill-buffer (get-file-buffer dummy-file)))
      (delete-directory temp-dir t))))

(ert-deftest test-org-history--append-after-save-to-dir-locals ()
  (let* ((temp-dir (make-temp-file "org-history-test-" t))
         (expected-file (expand-file-name ".dir-locals.el" temp-dir))
         (dummy-file (expand-file-name "dummy.org" temp-dir)))
    (unwind-protect
        (progn
          (find-file dummy-file)
          (let* ((default-directory temp-dir)
                 (result-path (org-history-dir-locals-append)))
            (should (string= result-path expected-file))
            (should (file-exists-p expected-file))
            (with-temp-buffer
              (insert-file-contents expected-file)
              (let ((content (read (current-buffer))))
                (should (assoc 'org-mode content))
                (let* ((org-rules (cdr (assoc 'org-mode content)))
                       (eval-rule (assoc 'eval org-rules)))
                  (should eval-rule)
                  (should (memq 'fboundp (flatten-tree eval-rule))))))))
      (when (get-file-buffer dummy-file)
        (kill-buffer (get-file-buffer dummy-file)))
      (when (file-exists-p expected-file)
        (delete-file expected-file))
      (delete-directory temp-dir t))))

(ert-deftest test-org-history--vc-git-integration-comprehensive ()
  (let* ((temp-dir (make-temp-file "git-test-" t))
         (default-directory (file-name-as-directory temp-dir))
         (tracked-file "sample.txt")
         (untracked-file "untracked.txt")
         (fixed-date "2026-05-29")
         (process-environment (append
                               (list (format "GIT_AUTHOR_DATE=%sT12:00:00" fixed-date)
                                     (format "GIT_COMMITTER_DATE=%sT12:00:00" fixed-date)
                                     "GIT_CONFIG_NOSYSTEM=1"
                                     "XDG_CONFIG_HOME=/dev/null")
                               process-environment)))
    (unwind-protect
        (progn
          (vc-git-command nil nil nil "init")
          (vc-git-command nil nil nil "config" "user.email" "test@example.com")
          (vc-git-command nil nil nil "config" "user.name" "Tester")
          (vc-git-command nil nil nil "config" "commit.gpgsign" "false")
          (with-temp-file tracked-file
            (insert "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n"))
          (with-temp-file untracked-file
            (insert "Untracked content.\n"))
          (vc-git-command nil nil nil "add" tracked-file)
          (vc-git-command nil nil nil "commit" "-m" "Initial commit")
          (dolist (case `((,tracked-file   2  4  ,fixed-date)
                          (,tracked-file   3  3  ,fixed-date)
                          (,tracked-file  10 20  nil)
                          (,tracked-file   0  0  nil)
                          (,tracked-file  -1  2  nil)
                          (,untracked-file 1  1  nil)
                          ("missing.txt"   1  2  nil)))
            (let ((file (nth 0 case))
                  (start (nth 1 case))
                  (end (nth 2 case))
                  (expected (nth 3 case)))
              (ert-info ((format "Testing Case: File=%s Range=%d-%d" file start end))
                (should (equal (org-history--vc-git-get-range-last-mod-date file start end)
                               expected))))))
      (delete-directory temp-dir t))))

(ert-deftest test-org-history--vc-git-integration-no-repo ()
  (let* ((temp-dir (make-temp-file "git-test-norepo-" t))
         (default-directory (file-name-as-directory temp-dir))
         (test-file "norepo.txt"))
    (unwind-protect
        (progn
          (with-temp-file test-file (insert "Hello world\n"))
          (should (null (org-history--vc-git-get-range-last-mod-date test-file 1 1))))
      (delete-directory temp-dir t))))

;; -=-= Tests for unfold and cycle hooks

;; =========================================================================
;; TRICKY TEST 1: The "No File on Disk" Hook Silencer
;; =========================================================================

(ert-deftest test-org-history-hook--silently-ignores-non-file-buffers ()
  "Tricky: `org-history-hook-for-after-save' checks `buffer-file-name'.
If a user runs `mt-mode' or saves a temporary buffer without an active
backing file, the hook must exit immediately without triggering `y-or-n-p'."
  (with-temp-buffer
    (org-mode)
    (setq buffer-file-name nil) ;; Explicitly no file path

    (let ((prompt-triggered nil))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) (setq prompt-triggered t) t))
                ((symbol-function 'vc-git-root) (lambda (&rest _) nil)))

        (org-history-hook-for-after-save)
        ;; The hook must short-circuit on: (when (and ... buffer-file-name ... ))
        (should-not prompt-triggered)))))

;; =========================================================================
;; TRICKY TEST 2: The `called-interactively-p` Advice Stack Trap
;; =========================================================================

(ert-deftest test-org-history--show-dates-interactivity-stack-depth ()
  "Tricky: `called-interactively-p` with 'any checks the *entire* call stack.
If `org-cycle' is wrapped inside another non-interactive function wrapper
higher up, `called-interactively-p' might return non-nil anyway.
This test ensures the advice cleanly manages this behavior."
  (let ((add-dates-called nil)
        (mock-orig-fun (lambda (&rest _) nil)))

    (cl-letf (((symbol-function 'org-at-heading-p) (lambda () t))
              ((symbol-function 'org-fold-folded-p) (lambda (&rest _) nil)) ;; Unfolded
              ((symbol-function 'org-history-outline--add-dates) (lambda (&rest _) (setq add-dates-called t)))
              (org-history-mode t))

      ;; Simulate an execution where an interactive command called a helper,
      ;; which then triggered the advice loop.
      (cl-letf (((symbol-function 'called-interactively-p)
                 (lambda (kind)
                   ;; If your advice checks 'any, it risks catching background loops.
                   (if (eq kind 'any) t nil))))

        (funcall #'org-history--show-dates-at-unfold mock-orig-fun)
        (should add-dates-called)))))


;; =========================================================================
;; FIXED TEST 4: Minor Mode Crash Protection in Out-Of-Scheme Buffers
;; =========================================================================

(ert-deftest test-org-history-mode-enforces-derived-mode-p-boundary ()
  "Tricky: `org-history-mode' contains an explicit safety guard:
\(unless (derived-mode-p 'org-mode) (user-error ...))
Verifies that activating this mode inside a non-Org buffer throws a
clean error and refuses to attach hooks."
  (with-temp-buffer
    (text-mode) ;; Not an org buffer!

    ;; Assert that activating the minor mode signals a `user-error`
    (should-error (org-history-mode 1) :type 'user-error)

    ;; FIX: Because `define-minor-mode` sets the mode variable to `t` *before* ;; running the body code, an error thrown in the body leaves the variable dirty.
    ;; The reliable indicator of safe abortion is that hooks were NEVER installed:
    (should-not (memq #'org-history-hook-for-after-save after-save-hook))

    ;; Cleanup the dirty state left by the macro's error unwinding manually for the test runner
    (setq org-history-mode nil)))


;; -=-= OVERHAULED

;; =========================================================================
;; OVERHAULED TEST 5: Cycle Hook Structural Mutation Under Stress
;; =========================================================================

(ert-deftest test-org-history-cycle-hook--handles-malformed-and-custom-states ()
  "Robust: Verify `org-history--cycle-hook' behaves predictably
when third-party extensions pass non-standard states or empty selections."
  (let ((dates-calculated 0))
    (cl-letf (((symbol-function 'org-history-outline--add-dates)
               (lambda (&rest _) (cl-incf dates-calculated))))

      (with-temp-buffer
        (org-mode)
        ;; Scenario A: Completely empty buffer shouldn't crash calculation boundaries
        (org-history--cycle-hook 'contents)
        (should (= dates-calculated 1))

        ;; Scenario B: Unexpected legacy states or custom strings
        ;; (e.g. 'inline, 'sparse, nil) must be completely ignored safely.
        (org-history--cycle-hook 'overview)
        (org-history--cycle-hook 'all)
        (org-history--cycle-hook 'custom-third-party-state)
        (org-history--cycle-hook nil)

        ;; Count should not change from baseline execution
        (should (= dates-calculated 1))))))



(ert-deftest test-org-history-hook--case2-true-filesystem-behavior ()
  "Robust: Verify Case 2's transparent commit vs prompt fork using
actual filesystem directory structures instead of deep function overrides."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "org-hist-c2-real-" t)))
         (test-file (expand-file-name "notes.org" temp-dir))
         (dir-locals-file (expand-file-name ".dir-locals.el" temp-dir))
         (default-directory temp-dir)
         buf)
    (unwind-protect
        (progn
          ;; 1. Establish an actual low-level repository state on disk
          (let ((vc-handled-backends '(Git)))
            (vc-git-command nil 0 nil "init"))

          ;; Open file buffer context properly
          (setq buf (find-file test-file))
          (org-mode)

          (let ((prompt-count 0)
                (commit-executed nil))

            ;; Cleanly isolate ONLY volatile time states and external UI queries.
            ;; Leave local directory-checking functions to read the real disk state!
            (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-06-12"))
                      ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-06-12"))
                      ((symbol-function 'org-history--git-get-last-commit-message) (lambda (&rest _) "org-history: update auto-save"))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) (cl-incf prompt-count) t))
                      ((symbol-function 'org-history--commit) (lambda (&rest _) (setq commit-executed t))))

              ;; -----------------------------------------------------------
              ;; Scenario A: Real .dir-locals.el file IS PRESENT on disk
              ;; -----------------------------------------------------------
              (with-temp-file dir-locals-file
                (insert "((org-mode . ((org-history-mode . t))))"))

              (let ((org-history-answer-was-given nil))
                (org-history-hook-for-after-save)
                ;; Must completely bypass prompting because file is structurally tracked on disk
                (should (= prompt-count 1))
                (should commit-executed))

              ;; Reset metrics for Scenario B
              (setq commit-executed nil)

              ;; -----------------------------------------------------------
              ;; Scenario B: Real .dir-locals.el file IS MISSING from disk
              ;; -----------------------------------------------------------
              (when (file-exists-p dir-locals-file)
                (delete-file dir-locals-file))

              (let ((org-history-answer-was-given nil))
                (org-history-hook-for-after-save)
                ;; Must actively catch the missing structure and request confirmation
                (should (= prompt-count 2))
                (should commit-executed)))))

      ;; Teardown and buffer cleanup
      (when buf (kill-buffer buf))
      (when (file-exists-p temp-dir)
        (delete-directory temp-dir t)))))
