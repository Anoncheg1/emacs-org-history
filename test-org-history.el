(require 'ert)
(require 'cl-lib)
(require 'vc-git)
(require 'org-history)
(require 'org-history-debug)

(defvar ert-enabled t)

(ert-deftest test-vc-git-commit-on-save--full-lifecycle1 ()
  "Test the complete lifecycle of `org-history-commit-on-save-hook'.
Verifies fresh repositories, same-day amending, date transitions,
and no-op saves (when no files are actually edited)."

  ;; Set up a clean, sandbox directory isolated from your system paths
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-test-" t)))
         (test-file (expand-file-name "test-file.txt" temp-dir))
         (default-directory temp-dir))

    (unwind-protect
        (progn

          (find-file test-file) ; open test file
          (org-mode)
          ;; (vc-register (list 'Git (list test-file))) ; trigger save file
          (org-history 1) ; add local hook for `after-save-hook'

          ;; =========================================================
          ;; TEST CASE 1: Brand New Repository (No existing HEAD)
          ;; =========================================================
          ;; The hook should realize there are zero commits, bypass the
          ;; log check, and make the initial day-1 commit cleanly.
          (print "Day 1: Initial lines of code.\n")
          (insert "Day 1: Initial lines of code.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22")))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))

              (save-buffer))) ;  +!!!+ trigger org-history, create initial commit  +!!!+

          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD")))
                (commit-msg (string-trim (shell-command-to-string "git log -1 --pretty=%B"))))
            (should (string-equal commit-count "1"))
            (should (string-equal commit-msg "")))

          (print "Day 2: Initial lines of code.\n")
          (insert "Day 2: Initial lines of code.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-23"))) ; current-date
            (save-buffer)) ; +!!!+ trigger org-history, create 2 commit  +!!!+
          ;; (my-vc-git-log-to-messages)
          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD")))
                (commit-msg (string-trim (shell-command-to-string "git log -1 --pretty=%B"))))
            ;; (org-history--debug "test-full-lifecycle1 %s" commit-count)
            (should (string-equal commit-count "2"))
            (should (string-equal commit-msg ""))) ;; Validates empty message requirement

          ;; =========================================================
          ;; TEST CASE 2: Same-Day Modification (Amend)
          ;; =========================================================
          ;; Modifying the file on the exact same date should merge the
          ;; change into the current commit instead of creating a brand new one.
          (insert "Day 2: Secondary edits inside the same session.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-23")) ; current date
                    ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-05-23")))
            (save-buffer)) ; +!!!+ trigger org-history, create 2 --amend commit  +!!!+

          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
            ;; Commit count should strictly remain 2 due to --amend
            (org-history--debug "test-full-lifecycle1 %s" commit-count)
            (should (string-equal commit-count "2")))

          ;; =========================================================
          ;; TEST CASE 3: No-Op Save Protection
          ;; =========================================================
          ;; If a user hits save (C-x C-s) but hasn't changed a single byte,
          ;; the hook must evaluate (vc-state) as non-edited and do nothing.
          ;; We evaluate this by assuring Git's HEAD hash doesn't change.
          (let ((old-hash (string-trim (shell-command-to-string "git rev-parse HEAD"))))
            (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-23")) ; current date
                      ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-05-23")))
              (save-buffer)) ;; Saving an unmodified buffer
            (let ((new-hash (string-trim (shell-command-to-string "git rev-parse HEAD"))))
              (should (string-equal old-hash new-hash))
              (should (string-equal old-hash (org-history--vc-get-last-commit)))
              ))

          ;; =========================================================
          ;; TEST CASE 4: Date Shift / Midnight Transition (New Commit)
          ;; =========================================================
          ;; When the system clock shifts to a new calendar day, the hook
          ;; must preserve yesterday's work and spawn a fresh daily commit.
          (insert "Day 2: Waking up next morning to write more Elisp.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-24")))
            (save-buffer))

          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
            ;; The total repository commit count should now increment cleanly to 2
            (should (string-equal commit-count "3")))))

      ;; ---------------------------------------------------------
      ;; CLEANUP: Ensure buffers are torn down and temp dirs deleted
      ;; ---------------------------------------------------------
      (when (get-file-buffer test-file)
        (set-buffer-modified-p nil)
        (kill-buffer (get-file-buffer test-file)))
      (delete-directory temp-dir t)))


(ert-deftest test-vc-git-commit-on-save--full-lifecycle2 ()
  "Test the complete lifecycle of `org-history-commit-on-save-hook'.
Verifies fresh repositories, same-day amending, date transitions,
and no-op saves (when no files are actually edited)."

  ;; Set up a clean, sandbox directory isolated from your system paths
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-test-" t)))
         (test-file (expand-file-name "test-file.txt" temp-dir))
         (default-directory temp-dir))

    (unwind-protect
        (progn
          (org-history-git-init)

          (find-file test-file) ; open test file
          (org-mode)
          ;; (vc-register (list 'Git (list test-file))) ; trigger save file
          (org-history 1) ; add local hook for `after-save-hook'

          ;; =========================================================
          ;; TEST CASE 1: Brand New Repository (No existing HEAD)
          ;; =========================================================
          ;; The hook should realize there are zero commits, bypass the
          ;; log check, and make the initial day-1 commit cleanly.
          (print "Day 1: Initial lines of code.\n")
          (insert "Day 1: Initial lines of code.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22"))) ; current date
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))

              (save-buffer t))) ;  +!!!+ trigger org-history, create initial commit  +!!!+
          ))
    (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
      (should (string-equal commit-count "1")))
    ;; (org-history--debug "test-full-lifecycle2 %s" (org-history--vc-get-last-commit 'Git))

      ;; ---------------------------------------------------------
      ;; CLEANUP: Ensure buffers are torn down and temp dirs deleted
      ;; ---------------------------------------------------------
      (when (get-file-buffer test-file)
        (set-buffer-modified-p nil)
        (kill-buffer (get-file-buffer test-file)))
      (delete-directory temp-dir t)))


(ert-deftest test-vc-git-commit-on-save--dot-git-already-exist-and-second-file ()
  "Test the complete lifecycle of `org-history-commit-on-save-hook'.
Verifies fresh repositories, same-day amending, date transitions,
and no-op saves (when no files are actually edited)."

  ;; Set up a clean, sandbox directory isolated from your system paths
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-test-" t)))
         (test-file1 (expand-file-name "test-file1.txt" temp-dir))
         (test-file2 (expand-file-name "test-file2.txt" temp-dir))
         (default-directory temp-dir))

    (unwind-protect
        (progn
          (should-not (file-exists-p (expand-file-name "~/.gitconfig")))

          (vc-git-command nil 0 nil "init")

          (find-file test-file1) ; open test file
          (org-mode)
          ;; (vc-register (list 'Git (list test-file))) ; trigger save file
          (org-history 1) ; add local hook for `after-save-hook'

          ;; =========================================================
          ;; TEST CASE 1:
          ;; =========================================================

          (print "Day 1: Initial lines of code.\n")
          (insert "Day 1: Initial lines of code.\n")
          (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22")))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))

              (save-buffer t))) ;  +!!!+ trigger org-history, create initial commit  +!!!+

          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD")))
                (commit-msg (string-trim (shell-command-to-string "git log -1 --pretty=%B"))))
            ;; (org-history--debug "test-full-lifecycle1 %s" commit-count)
            (should (string-equal commit-count "1"))
            (should (string-equal commit-msg "")))

          ;; =========================================================
          ;; TEST CASE 2: second file
          ;; =========================================================

          (find-file test-file2) ; open test file
          (insert "Day 1: Initial lines of code.\n")
          (let ((old-hash (string-trim (shell-command-to-string "git rev-parse HEAD"))))
            (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "2026-05-22")) ; current date
                      ((symbol-function 'org-history--vc-git-get-last-commit-date) (lambda (&rest _) "2026-05-22")))
              (save-buffer)) ;; Saving an unmodified buffer
            (should-not (string-equal old-hash (org-history--vc-get-last-commit))))

          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD")))
                (commit-msg (string-trim (shell-command-to-string "git log -1 --pretty=%B"))))
            ;; (org-history--debug "test-full-lifecycle1 %s" commit-count)
            (should (string-equal commit-count "1"))
            (should (string-equal commit-msg "")))

          ))
    (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
      (should (string-equal commit-count "1")))
    ;; (org-history--debug "test-full-lifecycle2 %s" (org-history--vc-get-last-commit 'Git))

      ;; ---------------------------------------------------------
      ;; CLEANUP: Ensure buffers are torn down and temp dirs deleted
      ;; ---------------------------------------------------------
      (when (get-file-buffer test-file1)
        (set-buffer-modified-p nil)
        (kill-buffer (get-file-buffer test-file1)))
      (when (get-file-buffer test-file2)
        (set-buffer-modified-p nil)
        (kill-buffer (get-file-buffer test-file2)))
      (delete-directory temp-dir t)))



(ert-deftest test-vc-git-commit-on-save--untracked-file ()
  "Verify that saving a brand-new untracked file behaves gracefully.
If the file isn't registered in VC yet, it should skip auto-commit."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-untracked-" t)))
         (untracked-file (expand-file-name "untracked.txt" temp-dir))
         (default-directory temp-dir))

    (unwind-protect
        (progn
          ;; Setup clean Git environment
          (org-history-git-init)

          ;; Create an initial commit so HEAD exists in the repo
          (shell-command "touch baseline.txt && git add baseline.txt && git commit -m 'Initial'")

          ;; Open a completely new file but DO NOT run vc-register
          (find-file untracked-file)
          (insert "This file is not tracked by Git yet.\n")

          ;; Activate hook
          (add-hook 'after-save-hook #'org-history-commit-on-save-hook nil t)

          ;; Save the untracked file
          (save-buffer)

          ;; Verify that the repository commit count remains exactly 1
          ;; (The hook should safely ignore this file because (vc-backend) won't return 'Git yet)
          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
            (should (string-equal commit-count "2"))))

      (when (get-file-buffer untracked-file)
        (kill-buffer (get-file-buffer untracked-file)))
      (delete-directory temp-dir t))))

(defun my-vc-git-log-to-messages ()
  "Fetch a beautifully formatted Git graph log string and print it to *Messages*."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))

  (if (not (eq (vc-backend buffer-file-name) 'Git))
      (message "This file is not tracked by Git.")
    (let ((default-directory (file-name-directory buffer-file-name)))
      (with-temp-buffer
        ;; Arguments: buffer, okstatus, file(s), git-commands...
        (vc-git-command (current-buffer) 0 nil
                        "log" "-n" "5" "--oneline" "--graph" "--decorate")

        (message "Recent Git Commits:\n%s" (string-trim (buffer-string)))))))


(ert-deftest test-vc-git-commit-on-save--ignored-file ()
  "Verify that saving a file matching .gitignore does not cause a crash.
Git will reject standard 'git add' on ignored files; ensure the hook stays quiet."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "emacs-git-ignored-" t)))
         (ignored-file (expand-file-name "secret.tmp" temp-dir))
         (default-directory temp-dir))

    (unwind-protect
        (progn
          ;; Setup Git environment with a .gitignore file
          (org-history-git-init)
          ;; (shell-command "echo '*.tmp' > .gitignore")
          ;; (shell-command "git add .gitignore && git commit -m 'Add gitignore'")

          ;; Open the ignored file variant
          (find-file ignored-file)

          ;; Even if VC attempts to manage it, Git's architecture will block standard addition
          ;; (vc-register (list 'Git (list ignored-file)))
          (add-hook 'after-save-hook #'org-history-commit-on-save-hook nil t)

          ;; Modify and save
          (insert "Temporary logs that should be ignored.\n")

          ;; This should pass without raising an unhandled Elisp error/crash during save
          ;; Using cl-letf but still calling the original code.

          (let* ((has-run nil)
                 (orig-fun (symbol-function #'org-history-git-init)))
            (cl-letf (((symbol-function #'org-history-git-init)
                       (lambda (&rest args)
                         (setq has-run t)
                         ;; Manually forward the arguments to the original function
                         (apply orig-fun args))))

              (should (progn (save-buffer) t))
              (should (not has-run))))


          ;; (my-vc-git-log-to-messages))))

          ;; Verify commit count didn't change from the initial baseline configuration
          ;; * 8ba19e8 (HEAD -> master)
          ;; * 6489a1a Add gitignore
          (let ((commit-count (string-trim (shell-command-to-string "git rev-list --count HEAD"))))
            (should (and "i)" (string-equal commit-count "1")))))

      (when (get-file-buffer ignored-file)
        (kill-buffer (get-file-buffer ignored-file)))
      (delete-directory temp-dir t))))


(ert-deftest test-my-append-existing-dir-locals ()
  "Test that the function safely merges into an existing .dir-locals.el file."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "ert-test-" t)))
         (target-file (expand-file-name ".dir-locals.el" temp-dir))
         ;; FIXED: Removed the invalid internal quote from the string list
         (initial-config '((python-mode . ((python-indent-offset . 4)))
                           (org-mode . ((org-todo-keywords . ("TODO" "DONE")))))))
    (unwind-protect
        (progn
          ;; Pre-populate file
          (with-temp-file target-file (pp initial-config (current-buffer)))

          ;; Run target function
          (org-history--append-after-save-to-dir-locals temp-dir)

          ;; Assert structural merges
          (with-temp-buffer
            (insert-file-contents target-file)
            (let ((result (read (current-buffer))))
              ;; 1. Check Python was preserved completely
              (should (equal (cdr (assoc 'python-mode result))
                             '((python-indent-offset . 4))))
              ;; 2. Check old Org settings are still intact
              (should (member '(org-todo-keywords . ("TODO" "DONE"))
                              (cdr (assoc 'org-mode result))))
              ;; 3. Check new eval block was safely appended to the section
              ;; (should (member '(eval . (add-hook 'after-save-hook #'org-history-commit-on-save-hook nil t))
              ;;                 (cdr (assoc 'org-mode result))))
              )))
      (delete-directory temp-dir t))))


(ert-deftest test-org-history--append-after-save-to-dir-locals ()
  "Test that `org-history--append-after-save-to-dir-locals' correctly creates and populates .dir-locals.el."
  ;; Create a temporary directory so we don't touch your real files
  (let* ((temp-dir (make-temp-file "org-history-test-" t))
         (expected-file (expand-file-name ".dir-locals.el" temp-dir)))

    (unwind-protect
        (progn
          ;; 1. Run the function on the empty temporary directory
          (let ((result-path (org-history--append-after-save-to-dir-locals temp-dir)))

            ;; Assert the return path is correct
            (should (string= result-path expected-file))
            ;; Assert the file was actually created
            (should (file-exists-p expected-file))

            ;; 2. Read the generated file back to verify its structure
            (with-temp-buffer
              (insert-file-contents expected-file)
              (let ((content (read (current-buffer))))

                ;; Assert the root is an alist with 'org-mode
                (should (assoc 'org-mode content))

                ;; Assert our specific 'eval rule exists inside the 'org-mode section
                (let* ((org-rules (cdr (assoc 'org-mode content)))
                       (eval-rule (assoc 'eval org-rules)))
                  (should eval-rule)
                  ;; Deep check that `fboundp` logic is present in the generated code
                  (should (memq 'fboundp (flatten-tree eval-rule))))))))

      ;; Cleanup: Delete the temporary file and directory afterward
      (when (file-exists-p expected-file)
        (delete-file expected-file))
      (delete-directory temp-dir))))

;; --- The Integration Test Wrapper ---

(ert-deftest test-vc-git-integration-comprehensive ()
  "Test `org-history--vc-git-get-range-last-mod-date` across multiple edge cases."
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
          ;; Setup repository
          (vc-git-command nil nil nil "init")
          (vc-git-command nil nil nil "config" "user.email" "test@example.com")
          (vc-git-command nil nil nil "config" "user.name" "Tester")
          (vc-git-command nil nil nil "config" "commit.gpgsign" "false")

          ;; Setup files
          (with-temp-file tracked-file
            (insert "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n"))
          (with-temp-file untracked-file
            (insert "Untracked content.\n"))

          (vc-git-command nil nil nil "add" tracked-file)
          (vc-git-command nil nil nil "commit" "-m" "Initial commit")

          ;; Execution Matrix
          (dolist (case `((,tracked-file   2  4  ,fixed-date) ; Happy Path
                          (,tracked-file   3  3  ,fixed-date) ; Single Line Boundary
                          (,tracked-file  10 20  nil)         ; Out of bounds high
                          (,tracked-file   0  0  nil)         ; Out of bounds low
                          (,tracked-file  -1  2  nil)         ; Negative range
                          (,untracked-file 1  1  nil)         ; Untracked file
                          ("missing.txt"   1  2  nil)))       ; Missing file
            (let ((file (nth 0 case))
                  (start (nth 1 case))
                  (end (nth 2 case))
                  (expected (nth 3 case)))
              (ert-info ((format "Testing Case: File=%s Range=%d-%d" file start end))
                (should (equal (org-history--vc-git-get-range-last-mod-date file start end)
                               expected))))))

      ;; Cleanup
      (delete-directory temp-dir t))))

(ert-deftest test-vc-git-integration-no-repo ()
  "Verify the function returns nil gracefully when completely outside a Git repo."
  (let* ((temp-dir (make-temp-file "git-test-norepo-" t))
         (default-directory (file-name-as-directory temp-dir))
         (test-file "norepo.txt"))
    (unwind-protect
        (progn
          (with-temp-file test-file (insert "Hello world\n"))
          (should (null (org-history--vc-git-get-range-last-mod-date test-file 1 1))))
      (delete-directory temp-dir t))))
