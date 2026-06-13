;;; org-history.el --- Show Dates for Org headers from vcs + auto-commit -*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>
;; Keywords: org, outline, vc
;; URL: https://codeberg.org/Anoncheg/emacs-org-history
;; Version: 0.1
;; Created: 30 may 2026
;; Package-Requires: ((emacs "29.1"))
;; SPDX-License-Identifier: AGPL-3.0-or-later

;;; License

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; Licensed under the GNU Affero General Public License, version 3 (AGPLv3)
;; <https://www.gnu.org/licenses/agpl-3.0.en.html>

;;; Commentary:

;; Configuration:
;; (add-to-list 'load-path "/path-to/emacs-org-history")
;; (require 'org-history)

;; Activation: M-x org-history

;; Customization: M-x customize-group RET org-history

;; Useful code:

;; (vc-backend buffer-file-name) or (vc-root-dir)
;; - Check if file is tracked, .git should exist

;; (vc-git-root buffer-file-name)
;; - Check if there is .git

;; How this works:

;; We accuratelly do "git commit --amend" for same date or create new
;;  commit if date changed.

;;; TODO:
;; - check org-history-directories
;; - make it work with outline mode.
;; - command to add current folder to list
;; - tests for -outlines  functions and itegral tests for minor mode

;; Require 29.1 for `org-fold-folded-p'

;;; Code:

;; Touch: I was looking for a job for many years. They are so much pigs, you even cant imagine.

(require 'vc)
(require 'vc-git)
(require 'org)
(require 'org-history-outline)
(require 'org-history-debug)

;; -=-= Variables

(defgroup org-history nil
  "Faces for OAI blocks."
  :tag "Org dates for outlines"
  :group 'org)

(defcustom org-history-git-init-commands
  '(("init") ; git init
    ("config" "user.name" "'(none)'") ; git config user.name '(none)'
    ("config" "user.email" "''")) ; git config user.email ''
  "List of argument lists passed to `vc-git-command` during initialization.
Also used to reinitialize if no commits was made."
  :type '(repeat (repeat string))
  :group 'org-history)

(defcustom org-history-gitignore-content '("*.elc"
                               "*~"
                               "#*#"
                               "/.emacs.desktop"
                               "/.emacs.desktop.lock"
                               "elpa/")
  "List of default patterns to write into a new .gitignore file.
Ignores: compiled files, backups, and lock files."
  :type '(repeat string)
  :group 'org-history)

(defcustom org-history-hide-dates nil
  "Non-nil means to hide dates after 2 seconds of mode activation.
Timer is used to observe File-local variables, because it happen after
 mode loading from dir-locals."
  :type 'boolean
  :group 'org-history)

;; ;; NOT USED
;; (defcustom org-history-directories nil
;;   "List of directories that processed without questions.
;; If `org-history-hook-for-after-save' set as global hook.
;; TODO: testing and refining required."
;;   :type 'string
;;   :group 'org-history)

(defvar-local org-history-answer-was-given nil
  "When non-nil, auto-commit at saving for this file is active.
Used for asking user whether to track current file.

Possible symbol values:
- nil			Tracking status not set yet.
- \='dont-track-file	Do NOT track this file.
- \='track-file		Track this file.")

;; -=-= functions: VC-git

(defun org-history--vc-reset-cache (&optional file)
  "Flush all common VC cache properties for current directory or FILE.
Uses `default-derectory'."
  (if file
      (vc-file-clearprops buffer-file-name)
    ;; else
    (when-let ((root (vc-root-dir)))
      (dolist (prop '(vc-backend vc-state vc-working-revision vc-name))
        (vc-file-setprop root prop nil)))))

(defun org-history--vc-git-get-last-commit-hash (&optional file)
  "Return string with the last commit or nil.
If FILE provided check commits only for file, otherwise any commit.
Uses variable `buffer-file-name'.
Note: `vc-git-working-revision' - accept directory as argument,
 `vc-working-revision' - only with file."
  (org-history-debug-print "org-history--vc-git-get-last-commit-hash N1 %s" file)
  (if file
      (when (vc-backend file)
        (vc-working-revision file)) ; require tracked file with commit
    ;; else
    (when-let ((path (vc-git-root buffer-file-name)))
      (vc-git-working-revision path))))

(defun org-history--vc-git-get-last-commit-date (&optional file)
  "Get commit date for FILE or for last commit.
Return string date YYYY-MM-DD or nil.
FILE should be tracked by git."
  (if file
      (when (vc-backend file)
        (when-let ((d (vc-git--run-command-string buffer-file-name "log" "-1" "--format=%as" file)))
          (string-trim d)))
    ;; else
    (when-let ((d (vc-git--run-command-string nil "show" "-s" "--format=%as")))
    (string-trim d))))

(defun org-history--vc-add-file (file &optional backend)
  "Track FILE.
Uses `default-derectory'.
Optional argument BACKEND is Git or may be other."
  ;; Clear Emacs VC cache so it realizes Git now exists
  (vc-file-clearprops file)

  (unless (vc-backend file) ; never added
    (vc-register (list (or backend 'Git) (list file))))

  ;; `vc-register' have a bug, rise error if file 'edited and was added before, but not now
  (vc-call-backend (or backend 'Git) 'register (list file))

  ;; Refresh the state to update vc-state immediately
  (vc-refresh-state))

;; NOT USED
(defun org-history--vc-git-unstage-file (file)
  "Unstage FILE using git restore --staged via vc-git primitives."
  (interactive "fFile to unstage: ")
  ;; Ensure the file actually belongs to a Git repository
  (if (eq (vc-backend file) 'Git)
      (progn
        (with-temp-buffer
          ;; vc-git--call takes: (buffer command &rest args)
          ;; file-local-name strips remote file prefixes (like TRAMP) if present
          (vc-git--call t "restore" "--staged" (file-local-name file)))

        ;; CRITICAL: Reset Emacs's internal VC cache so it notices the file is unstaged
        (vc-file-setprop file 'vc-state nil)
        (vc-file-setprop file 'vc-working-revision nil)

        (message "Successfully unstaged %s" (file-name-nondirectory file)))
    (error "This file is not in a Git repository")))

(defun org-history--vc-git-get-range-last-mod-date (file start end)
  "Return the last modification date (YYYY-MM-DD) for lines START to END in FILE.
Returns nil if FILE is not in Git, range is invalid, or no commits exist.
Uses `default-directory'."
  (when (and (file-exists-p file)
             (> start 0)
             (>= end start)
             default-directory
             (vc-git-responsible-p default-directory))
    (with-temp-buffer
      (condition-case nil
          (when (zerop (vc-git-command
                        t 0 nil
                        "log" "-1" "--pretty=format:%as" "-s"  ; Added "-s" to suppress the diff patch
                        (format "-L%d,%d:%s" start end file)))
            (let ((output (buffer-string)))
              (unless (string-empty-p output)
                (string-trim output))))
        (error nil)))))

(defun org-history--vc-git-blame-file (file)
  "Return a hash table mapping line numbers to modification dates for FILE.

An optimized version of `org-history--vc-git-get-range-last-mod-date'.
Uses `default-directory'.

The returned hash table uses `eql' as its test, where keys are line
numbers (integers starting from 1) and values are plain strings representing
the last modification date formatted as \"YYYY-MM-DD\".

If FILE does not exist, is not registered under Git, or the underlying
`git blame' command fails, an empty hash table is returned.

To minimize memory allocation and prevent Garbage Collection (GC) pressure,
consecutive lines that share identical modification dates point to the exact
same string object in memory.  The search is strictly bounded line-by-line
to prevent layout syntax errors from desynchronizing the line counter."
  (when (and (file-exists-p file)
             default-directory
             ;; (org-history--vc-git-get-last-commit-hash file) ; have commits?
             (vc-git-responsible-p default-directory))
    (let ((line-dates (make-hash-table :test 'eql))
          (line-num 1)
          last-date-str)
      (when (and (file-exists-p file) (vc-git-responsible-p default-directory))
        (with-temp-buffer
          (when (zerop (vc-git-command t 0 nil "blame" "--date=short" "-c" file))
            (goto-char (point-min))
            ;; Optimization 1: Anchor search to the current line to limit regex engine workload
            (while (re-search-forward "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" (line-end-position) t)
              (let ((date-str (match-string-no-properties 1)))
                ;; Optimization 2: String Deduplication to drastically cut GC pressure
                (if (and last-date-str (string= date-str last-date-str))
                    (puthash line-num last-date-str line-dates)
                  (setq last-date-str date-str)
                  (puthash line-num date-str line-dates)))
              (setq line-num (1+ line-num))
              ;; Optimization 3: Move explicitly to the next line to avoid double-matching
              ;; if a code comment accidentally contains a date string.
              (forward-line 1)))))
      line-dates)))

;; -=-= function: add record to .dir-locals.el
;; ----------------------- append-after-save ---------------
;; [Original Config] ---> Extract 'org-mode entries (File A's rules)
;;                              |
;;                              v
;;                      Add File B's new rule to the list
;;                              |
;;                              v
;; [Strip old org-mode] -> [Insert combined rules] -> [Save file]
;;
;; Result .dir-locals.el example:
;; ((org-mode
;;   (eval when
;;         (and (fboundp 'org-history-mode) buffer-file-name
;;              (file-equal-p buffer-file-name
;;                            (expand-file-name "c.org" default-directory)))
;;         (org-history-mode 1))
;;   (eval when
;;         (and (fboundp 'org-history-mode) buffer-file-name
;;              (file-equal-p buffer-file-name
;;                            (expand-file-name "b.org" default-directory)))
;;         (org-history-mode 1))

(defun org-history--dir-locals-p (&optional rel-file-name config)
  "Check if there is rule for file in .dir-locals.el.
Files is REL-FILE-NAME or BUFFER-FILE-NAME.
Optional argument CONFIG is parsed .dir-locals containing an `org-mode`
 rule for REL-FILE-NAME to activate `org-mistory-mode'.
Use `default-directory' and variable `buffer-file-name' for config reading if
 CONFIG is not provided."
  (org-history-debug-print "org-history--dir-locals-p N1 %s" rel-file-name)
  (org-history-debug-print "org-history--dir-locals-p N1" config)
  (let* ((rel-file-name (or rel-file-name (file-relative-name buffer-file-name default-directory)))
         (config (or config (when (file-exists-p ".dir-locals.el")
                              (with-temp-buffer
                                (insert-file-contents ".dir-locals.el")
                                (ignore-errors (read (current-buffer)))))))
         (org-entries (cdr (assoc 'org-mode config)))) ; return nil if config is nil
    (when org-entries
      (catch 'found
        (dolist (entry org-entries nil) ; returns nil if loop finishes naturally
          (when (and (eq (car-safe entry) 'eval)
                     (string-match-p (regexp-quote rel-file-name) (format "%S" entry)))
            (throw 'found t)))))))


(defun org-history-dir-locals-append ()
  "Add an `org-history-mode' activation to TARGET-DIR/.dir-locals.el.
Uses variable `buffer-file-name' and `default-directory' variables.
Safely merges with existing mode settings without overwriting rules for
 other files.
Return .dir-locals.el file path if added."
  (interactive "DSelect directory for .dir-locals.el: ")
  (unless buffer-file-name
    (user-error "org-history: Current buffer is not visiting a file"))
  (unless default-directory
    (user-error "org-history: No default-directory"))

  (let* ((file-path (expand-file-name ".dir-locals.el" default-directory))
         (rel-file-name (file-relative-name buffer-file-name default-directory))
         ;; 1. Read existing config ONCE safely
         (config (when (file-exists-p file-path)
                   (with-temp-buffer
                     (insert-file-contents file-path)
                     (ignore-errors (read (current-buffer))))))
         ;; 2. Generate the new rule
         (new-rule `(eval . (when (and (fboundp 'org-history-mode)
                                       buffer-file-name
                                       (file-equal-p buffer-file-name
                                                     (expand-file-name ,rel-file-name default-directory)))
                              (org-history-mode 1)))))

    (unless (org-history--dir-locals-p rel-file-name config)
      ;; (message ".dir-locals.el is already configured for %s" rel-file-name)
      ;; 3. Destructive-safe update of the alist using built-in alist-get
      (let ((org-entries (cdr (assoc 'org-mode config))))
        (setf (alist-get 'org-mode config) (cons new-rule org-entries)))

      ;; 4. Pretty-print back to file
      (with-temp-file file-path
        (let (print-level print-length)
          (pp config (current-buffer))))
      (message "Successfully synchronized .dir-locals.el for %s" rel-file-name)
      file-path)))

;; -=-= functions: init .git

(defun org-history-git-init (&optional first-file)
  "Execute the custom Git initialization commands sequentially.
Optional argument FIRST-FILE is used for the first file to init git
 repostiry or .gitignore if not exist or .dir-locals.el
FIRST-FILE should be a name of file in `default-directory'.
Create .gitignore and .dir-locals.el.
Warning, `vc-root-dir' will return nil until first commit will be made.
Safe to call with existing .git.
Use `default-directory'."
  (interactive)
  (let ((vc-handled-backends '(Git)))
    ;;  Step 0 : clear vc catch
    (org-history--vc-reset-cache)
    (when first-file
      (org-history--vc-reset-cache first-file))
    ;; Step 1: Create the .gitignore file safely
    ;; (we need at leas one file to init initialize)
    (let ((first-f (expand-file-name
                    (if (and first-file (file-exists-p first-file))
                        first-file
                      ;; else
                      (if (not (file-exists-p ".gitignore"))
                          ".gitignore"
                        ;; else
                        ".dir-locals.el"
                        ;; else
                        ;; (user-error "Cant init git in for org-history: .gitignore and .elpaignore is exist")
                        ))
                    default-directory)))
      ;; Create  .dir-locals.el
      (org-history-dir-locals-append)

      ;; Create  .gitignore
      (when (not (file-exists-p ".gitignore"))
        (with-temp-file  ".gitignore"
          (insert (mapconcat #'identity org-history-gitignore-content "\n") "\n")
          ;; (save-buffer
          (write-file ".gitignore")
          (basic-save-buffer)))

      ;; Step 1: Initialize the Git repository
      (dolist (args org-history-git-init-commands)
        ;; 'apply' lets us unpack the 'args' list directly into the function call
        (apply #'vc-git-command nil 0 nil args))

      (message "Initialized Git repository...")

      ;; Step 3: add first file to finish initialization
      (org-history--vc-add-file first-f 'Git)

      ;; ;; Refresh the state to update vc-state immediately
      ;; (vc-refresh-state)
      ;; (org-history-debug-print "org-history-git-init" (org-history--vc-git-status))
      ;; (vc-responsible-backend default-directory) ; fix vc-root-dir to return without first commit
      (setq org-history-answer-was-given 'track-file)

      ;; Commit is not required, add is enough
      (message "Git initialized %s with file %s!" default-directory (file-relative-name first-f)))))


;; -=-= functions: check-hook-scope (OLD)

(defun org-history--check-hook-scope (hook func)
  "Check if FUNC is bound to HOOK as :global, :local, :both, or nil."
  (cond ((and (memq func (default-value hook))
              (local-variable-p hook)
              (memq t (memq func (and (boundp hook) (symbol-value hook)))))
         :both)
        ((and (local-variable-p hook)
              (memq t (memq func (and (boundp hook) (symbol-value hook)))))
         :local)
        ((memq func (default-value hook))
         :global)))

;; -=-= hook: after-save
(defun org-history--git-get-last-commit-message (&optional file)
  "Get any last Git commit message, or for FILE if provided.
Returns the trimmed message string, or nil if an error occurs (e.g., no
 commits exist)."
  (when (or (not file) (and file (file-exists-p file)))
    ;; The first element here must be the command string "log", NOT nil.
    (let ((args (if file
                    (list "log" "-1" "--pretty=%B" "--" (file-relative-name file))
                  (list "log" "-1" "--pretty=%B"))))
      (with-demoted-errors "org-history (git log error): %S"
        (when-let ((output (apply #'vc-git--run-command-string nil args)))
          (string-trim output))))))

(defun org-history--commit (last-commit-date)
  "Execute the commit or amend routines based on the presence of LAST-COMMIT-DATE.
Uses variable `buffer-file-name'.
Assumes tracking confirmation has already been validated and set."
  (let ((current-date (format-time-string "%F")) ; Y-%m-%d
        (last-commit-message (when last-commit-date
                               (org-history--git-get-last-commit-message))))
    (if (and last-commit-date
             (string-equal last-commit-date current-date)
             (string-prefix-p "org-history" last-commit-message))

        ;; Sub-Case A: Amend day's existing transaction
        (progn
          (org-history--vc-add-file buffer-file-name 'Git)
          (vc-git-command nil 0 nil "commit" "--amend" "--allow-empty" "--no-edit" "--date=now")
          (message "VC-Git: Amended existing commit for today."))

      ;; Stage file changes and commit
      (org-history--vc-add-file buffer-file-name 'Git)
      (vc-git-command nil 0 nil "commit" "-m" "org-history")
      (message "VC-Git: Created new empty-message commit."))))


(defun org-history-hook-for-after-save ()
  "Hook for `org-mode' buffers run after saving a file.

When an org file is saved, check Git tracking status and `org-history'
 configuration.  Prompts to enable tracking if needed, initializes Git
 repository if absent, amends or creates Git commits, updates
 `.dir-locals.el`, and synchronizes version control cache as
 appropriate."
  (when (and (not (eq org-history-answer-was-given 'dont-track-file))
             buffer-file-name
             default-directory)
    (let ((git-root (vc-git-root buffer-file-name))
          (is-file-tracked (eq 'Git (vc-backend buffer-file-name)))
          (current-date (format-time-string "%F"))) ; Y-%m-%d
      (let ((default-directory (or git-root
                                   default-directory)))

        ;; (y-or-n-p (format "org-history: Add record for this file in\n%s? " (expand-file-name ".dir-locals.el" default-directory))))
        (vc-file-clearprops buffer-file-name)
        (let ((last-commit-date-file
               (when is-file-tracked (org-history--vc-git-get-last-commit-date buffer-file-name)))
              (last-commit-message-global
               (when is-file-tracked (org-history--git-get-last-commit-message)))
              (rel-file-name (file-relative-name buffer-file-name default-directory)))

          ;; Clean up VC internal property cache to ensure fresh Git statuses
          ;; (vc-file-clearprops buffer-file-name)

          ;; cases:
          ;; - Case 1: No Git repository exists at all
          ;; - Case 2: Git repo exists + same day + org-history prefix -> Transparently Amend (No prompt)
          ;; - Case 3: Git repo exists, but requires a new commit or initial tracking approval
          (org-history-debug-print "org-history-hook-for-after-save N1 git-root=%s is-file-tracked=%s current-date=%s" git-root is-file-tracked current-date)
          (org-history-debug-print "org-history-hook-for-after-save N1 default-directory=%s last-commit-date-file=%s last-commit-message-global=%s" default-directory last-commit-date-file last-commit-message-global)

          ;; --- CASES ---
          (cond
           ;; Case 1: No Git repository exists at all
           ((not git-root)
            (org-history-debug-print "org-history-hook-for-after-save Case1")
            (if (y-or-n-p (format "org-history: Do git init and activate auto-commit for this file in\n%s? " default-directory))
                (progn
                  (org-history-git-init rel-file-name) ; add .dir-locals.el
                  (if org-history-hide-dates
                      (message "org-history: dates was not shown because of org-history-hide-dates variable.")
                       ;; else
                    (org-history-outline-add-dates))
                  (setq org-history-answer-was-given 'track-file))
              (setq org-history-answer-was-given 'dont-track-file)))

           ;; Case 2: Git repo exists + same day + org-history prefix -> Transparently Amend (No prompt)
           ((and last-commit-date-file
                 (string-equal last-commit-date-file current-date)
                 (string-prefix-p "org-history" last-commit-message-global))
            (org-history-debug-print "org-history-hook-for-after-save Case2 %s"  (org-history--dir-locals-p rel-file-name)  (not org-history-answer-was-given))
            ;; 1. Ensure we have a tracking decision if we don't already
            (when (and (not (org-history--dir-locals-p rel-file-name)) ; dir-locals
                       (not org-history-answer-was-given))
              (let ((prompt (format "org-history: track this file and add record for this file in\n%s? " (expand-file-name ".dir-locals.el" default-directory))))
                (setq org-history-answer-was-given (if (y-or-n-p prompt) 'track-file 'dont-track-file)))
              ;; 2. Create  .dir-locals.el
              (when (eq org-history-answer-was-given 'track-file)
                (org-history-dir-locals-append)))
            ;; unconditionally
            (org-history--commit last-commit-date-file))

           ;; Case 3: Git repo exists, but requires a new commit or initial tracking approval
           (t
            (org-history-debug-print "org-history-hook-for-after-save Case3")
            (let ((dir-locals (org-history--dir-locals-p rel-file-name)))
              ;; 1. Ensure we have a clear tracking decision
              (unless (and org-history-answer-was-given dir-locals)
                (let ((prompt-msg (format "org-history: enable auto-commit on save this file and in\n%s? "
                                          (expand-file-name ".dir-locals.el" default-directory))))
                  (setq org-history-answer-was-given
                        (if (y-or-n-p prompt-msg) 'track-file 'dont-track-file))))

              ;; 2. Execute tracking logic if allowed
              (when (eq org-history-answer-was-given 'track-file)
                ;; Ensure Git repo is initialized with baseline settings if empty
                (unless (vc-git--run-command-string nil "log" "-1")
                  (let ((inhibit-message t)) ; Keep the echo area clean during init loop
                    (dolist (args org-history-git-init-commands)
                      (apply #'vc-git-command nil 0 nil args))))

                ;; Create  .dir-locals.el
                (when (not dir-locals)
                  (org-history-dir-locals-append))

                (org-history--commit last-commit-date-file)
                (unless last-commit-date-file
                  (unless org-history-hide-dates
                    (org-history-outline-add-dates)))))))

          ;; Synchronize cache once more post-execution for UI updates (e.g., modeline)
          (vc-file-clearprops buffer-file-name))))))

;; -=-= function: headers folding
(defun org-history--show-dates-at-unfold (orig-fun &rest args)
  "Add dates for subheaders at unfolding.
Checks if user interactively unfolded a heading.
Triggered after `org-cycle'.
Reliably check for interactive execution using :around advice.
Argument ORIG-FUN is `org-cycle' and its ARGS."
  ;; 1. Check interactivity FIRST while org-cycle is at the top of the stack
  (let ((interactive-call (called-interactively-p 'any)))
        ;; (hook-placed (org-history--check-hook-scope 'after-save-hook #'org-history-hook-for-after-save))) ; old

    ;; 2. Run the original org-cycle command so the heading actually changes state
    (apply orig-fun args)

    ;; 3. Now perform your post-execution visibility checks safely
  (when (and (bound-and-true-p org-history-mode)
             interactive-call			; 1. Only run if called interactively
             (org-at-heading-p)		; 2. Only run if cursor is on a heading
             (not (save-excursion		; 3. Ensure heading is currently open
                    (end-of-line)
                    (org-fold-folded-p nil 'outline)))) ; 'headline ?
    (let ((vc-handled-backends '(Git)))
        (let ((start (save-excursion (forward-line 1) (point)))
              (end (save-excursion (org-end-of-subtree t t) (point))))
          (org-history-outline-add-dates start end))
        ;; (message "Interactively unfolded heading!")
        ))))

(defun org-history--cycle-hook (state)
  "Triggered by `org-shifttab' from `org-cycle-internal-global' after cycling.
STATE may be `overview', `contents', or `all'."
  (when (eq state 'contents)
    (let ((vc-handled-backends '(Git)))
      (org-history-outline-add-dates (point-min) (point-max)))))

;; -=-= interactive: hide dates
(defun org-history-hide ()
  "Hide dates only."
  (interactive)
  (advice-remove 'org-cycle #'org-history--show-dates-at-unfold)
  (remove-hook 'org-cycle-hook #'org-history--cycle-hook t)
  (org-history-outline-clear-all-org-date-overlays))

(defun org-history-show ()
  "Hide dates only."
  (interactive)
  (unless
    (when (or org-history-mode
              (memq 'org-history--cycle-hook org-cycle-hook)
              (y-or-n-p (format "You want to see dates while org-history is not active?")))
      (advice-add 'org-cycle :around #'org-history--show-dates-at-unfold '((local . t)))
      (add-hook 'org-cycle-hook #'org-history--cycle-hook nil t)
      (org-history-outline-add-dates))))


;; -=-= minor mode
;;;###autoload
(define-minor-mode org-history-mode
  "Minor mode for `org-mode' to showing date of last modified per outlier."
  :init-value nil
  ;; :keymap oai-mode-map
  :group 'org-nistory
  (unless (derived-mode-p 'org-mode)
    (user-error "Org-history minor mode failed to activate in buffer %s, not Org mode" (buffer-name (current-buffer))))
  (if org-history-mode
      (progn
        (let ((vc-handled-backends '(Git)))
          ;; no last commit - ask user to init .git
          (when (not (org-history--vc-git-get-last-commit-hash)) ; any commits for file?
            (if (y-or-n-p (format "org-history: Do git init in %s? " default-directory))
                (progn
                  (org-history-git-init (file-relative-name buffer-file-name default-directory)) ; (setq org-history-answer-was-given 'track-file))
                  (org-history--commit nil)) ; add commit
              ;; else
              (setq org-history-answer-was-given 'dont-track-file)))
          (org-history-outline-add-dates))
        (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
        (advice-add 'org-cycle :around #'org-history--show-dates-at-unfold '((local . t)))
        (add-hook 'org-cycle-hook #'org-history--cycle-hook nil t)
        (let ((orig-buffer (current-buffer))) ; lexical binding
          (run-with-timer
           2.5 nil ; we use timer to to be able to see File-Local variables
           (lambda ()
             ;; Because of lexical binding, orig-buffer is automatically captured
             (if (buffer-live-p orig-buffer)
                 (with-current-buffer orig-buffer
                   (when org-history-hide-dates
                     (org-history-hide))))))))

    ;; else - off
    (advice-remove 'org-cycle #'org-history--show-dates-at-unfold)
    (remove-hook 'after-save-hook #'org-history-hook-for-after-save t)
    (remove-hook 'org-cycle-hook #'org-history--cycle-hook t)
    (org-history-outline-clear-all-org-date-overlays)

    (kill-local-variable 'org-history-answer-was-given)
    (message "org-history is disabled.")))

(defalias 'org-history #'org-history-mode)


;; ;; NOT USED
;; (defun org-history--check-hook-directories () ; OLD TODO: replace with minor global mode
;;   (or (eq hook-placed :local)
;;       (eq hook-placed :both)
;;       (and (eq hook-placed :global)
;;            (catch 'found
;;              (dolist (path org-history-directories)
;;                (when (file-equal-p dir path)
;;                  (throw 'found t)))
;;              nil))))



;;; provide

(provide 'org-history)

;;; org-history.el ends here
