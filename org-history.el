;;; org-history.el --- org-mode headers dates with git -*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>
;; Keywords: org, outline, hideshow
;; URL: https://codeberg.org/Anoncheg/emacs-org-history
;; Version: 0.1
;; Created: 30 may 2026
;; Package-Requires: ((emacs "27.1"))
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

;; Check if file is tracked:
;; (vc-backend buffer-file-name)

;; Check if there is .git
;; (vc-git-root buffer-file-name)

;; How this works:

;; We accuratelly do "git commit --amend" for same date or create new
;;  commit if date changed

;;; TODO:
;; - check org-history-directories
;; - make it work with outline mode.
;; - command to add current folder to list
;; - tests for -outlines  functions and itegral tests for minor mode
;; - now we check if org-history-hook-for-after-save is bound as local
;;  or global hook. Why we need mode? how they work togeter?
;;  - ability to track only one file or while folder
;;  - check for error if .git exist with commits but error at commit
;;  because of no credentials.

;;; Code:

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

(defcustom gitignore-content '("*.elc"
                               "*~"
                               "#*#"
                               "/.emacs.desktop"
                               "/.emacs.desktop.lock"
                               "elpa/")
  "List of default patterns to write into a new .gitignore file.
Ignores: compiled files, backups, and lock files."
  :type '(repeat string)
  :group 'org-history)

(defcustom org-history-directories nil
  "List of directories that processed without questions.
If `org-history-hook-for-after-save' set as global hook.
TODO: testing and refining required."
  :type 'string
  :group 'org-history)

(defvar-local org-history-track-file nil
  "When non-nil, auto-commit at saving for this file is active.
Used for asking user whether to track current file.

Possible values are:
- nil            : Tracking status not set yet.
- 'dont-track-file: Do NOT track this file.
- 'track-file     : Track this file.")

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

(defun org-history--vc-get-last-commit (&optional backend)
  "Return string with the last commit or nil.
Uses `default-derectory'."
  (when-let ((root (vc-root-dir))) ; not nil even without commits
    (vc-working-revision root (or backend 'Git))))

;; (defun org-history--vc-git-get-last-commit-date ()
;;   "Return string with the last commit date or nil.
;; Uses `default-derectory'."
;;   (when-let ((rev (org-history--vc-get-last-commit 'Git)))
;;     (with-temp-buffer
;;       ;; 't' makes this synchronous so the buffer fills before we read it
;;       (vc-git-command (current-buffer) 0 nil
;;                       "show" "-s" "--format=%as" rev)
;;       (string-trim (buffer-string)))))

(defun org-history--vc-git-get-last-commit-date ()
  "Return string with the last commit date or nil.
Uses `default-derectory'."
  (when-let ((d (vc-git--run-command-string nil "show" "-s" "--format=%as")))
    (string-trim d)))


(defun org-history--vc-add-file (file &optional backend)
  "Track file.
Uses `default-derectory'."
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
             (org-history--vc-git-get-last-commit-date)
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

;; -=-= functions: init .git

(defun org-history-git-init (&optional first-file)
  "Execute the custom Git initialization commands sequentially.
Optional argument FIRST-FILE is used for the first file to init git
 repostiry if .gitignore is already exist, otherwise .elpaignore is
 used.  FIRST-FILE should be a name of file in `default-directory'.
Warning, `vc-root-dir' will return nil until first commit will be made.
Use `default-directory'."
  (interactive)
  ;;  Step 0 : clear vc catch
  (org-history--vc-reset-cache)
  (when first-file
    (org-history--vc-reset-cache first-file))
    ;; Step 1: Create the .gitignore file safely
  ;; (we need at leas one file init initialize)
  (let ((first-f (expand-file-name
                  (if (not (file-exists-p ".gitignore"))
                      ".gitignore"
                    ;; else
                    (if (and first-file (file-exists-p first-file))
                        first-file
                      ;; else
                      ;; (if (not (file-exists-p ".dir-locals.el"))
                      ".dir-locals.el"
                        ;; else
                        ;; (user-error "Cant init git in for org-history: .gitignore and .elpaignore is exist")
                        ))
                  default-directory))
        (dir-locals (org-history--append-after-save-to-dir-locals default-directory)))

    ;; Create  .gitignore
    (when (not (file-exists-p ".gitignore"))
      (with-temp-file  ".gitignore"
        (insert (mapconcat 'identity gitignore-content "\n") "\n")
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
    ;; (org-history--debug "org-history-git-init" (org-history--vc-git-status))
    ;; (vc-responsible-backend default-directory) ; fix vc-root-dir to return without first commit
    ;; (print (vc-root-dir))
    (setq org-history-track-file 'track-file)

    ;; Commit is not required, add is enough
    (message "Registered .gitignore and %s with Git!" default-directory)))


;; -=-= functions: check-hook-scope

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

;; -=-= function: add record to .dir-locals.el

;; (defun org-history--append-after-save-to-dir-locals (target-dir)
;;   "Safely add or merge the local after-save-hook into TARGET-DIR/.dir-locals.el.
;; Add: function to `after-save-hook' and enable `org-history-track-file'.
;; Return .dir-locals.el path."
;;   (interactive "DSelect directory for .dir-locals.el: ")
;;   (let* ((file-path (expand-file-name ".dir-locals.el" (or target-dir default-directory)))
;;          ;; Your existing hook injection rule
;;          (new-rule '(eval . (if (fboundp 'org-history-hook-for-after-save)
;;                                 (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
;;                               (lwarn 'org-history :warning "`org-history` is not available; auto-commit on save disabled."))))
;;          ;; NEW: The variable tracking rule
;;          (track-rule '(org-history-track-file . track-file))
;;          ;; 1. Read file if it exists, otherwise start with a clean nil list
;;          (config (and (file-exists-p file-path)
;;                       (with-temp-buffer
;;                         (insert-file-contents file-path)
;;                         (ignore-errors (read (current-buffer)))))))

;;     ;; 2. Seamlessly update or create the 'org-mode section
;;     ;; Inject the eval rule if missing
;;     (unless (member new-rule (cdr (assoc 'org-mode config)))
;;       (setf (alist-get 'org-mode config) (cons new-rule (cdr (assoc 'org-mode config)))))

;;     ;; NEW: Inject the org-history-track-file rule if missing
;;     (unless (member track-rule (cdr (assoc 'org-mode config)))
;;       (setf (alist-get 'org-mode config) (cons track-rule (cdr (assoc 'org-mode config)))))

;;     ;; 3. Write it back out cleanly
;;     (with-temp-file file-path
;;       (let (print-level print-length)
;;         (pp config (current-buffer))))
;;     (message "Successfully synchronized .dir-locals.el")
;;     file-path))

;; (defun org-history--append-after-save-to-dir-locals (target-dir)
;;   "Safely add or merge the local after-save-hook into TARGET-DIR/.dir-locals.el.
;; Add: function to `after-save-hook' globally for org-mode, but enable
;; `org-history-track-file' only for the current `buffer-file-name'.
;; Return .dir-locals.el path."
;;   (interactive "DSelect directory for .dir-locals.el: ")
;;   (unless buffer-file-name
;;     (user-error "Current buffer is not visiting a file"))

;;   (let* ((target-dir (expand-file-name (or target-dir default-directory)))
;;          (file-path (expand-file-name ".dir-locals.el" target-dir))
;;          ;; 1. Calculate the relative file name for the current buffer
;;          (rel-file-name (file-relative-name buffer-file-name target-dir))

;;          ;; Your existing hook injection rule for all org-mode files
;;          (new-rule '(eval . (if (fboundp 'org-history-hook-for-after-save)
;;                                 (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
;;                               (lwarn 'org-history :warning "`org-history` is not available; auto-commit on save disabled."))))
;;          ;; The variable tracking rule applied only to this specific file
;;          (track-rule '(org-history-track-file . track-file))

;;          ;; Read file if it exists, otherwise start with a clean nil list
;;          (config (and (file-exists-p file-path)
;;                       (with-temp-buffer
;;                         (insert-file-contents file-path)
;;                         (ignore-errors (read (current-buffer)))))))

;;     ;; 2. Update the general 'org-mode section for the hook
;;     (unless (member new-rule (cdr (assoc 'org-mode config)))
;;       (setf (alist-get 'org-mode config) (cons new-rule (cdr (assoc 'org-mode config)))))

;;     ;; 3. Update the file-specific section for tracking
;;     ;; In .dir-locals.el, string keys represent specific sub-paths/files
;;     (unless (member track-rule (cdr (assoc rel-file-name config)))
;;       (setf (alist-get rel-file-name config nil nil #'equal)
;;             (cons track-rule (cdr (assoc rel-file-name config #'equal)))))

;;     ;; 4. Write it back out cleanly
;;     (with-temp-file file-path
;;       (let (print-level print-length)
;;         (pp config (current-buffer))))
;;     (message "Successfully synchronized .dir-locals.el for %s" rel-file-name)
;;     file-path))

;; (defun org-history--append-after-save-to-dir-locals (target-dir)
;;   "Safely add or merge a file-specific activation rule into TARGET-DIR/.dir-locals.el.
;; This activates `org-history-mode' (or your specific minor mode) ONLY when
;; the current file is opened.
;; Return .dir-locals.el path."
;;   (interactive "DSelect directory for .dir-locals.el: ")
;;   (unless buffer-file-name
;;     (user-error "Current buffer is not visiting a file"))

;;   (let* ((target-dir (expand-file-name (or target-dir default-directory)))
;;          (file-path (expand-file-name ".dir-locals.el" target-dir))
;;          ;; Calculate the relative file name for the current buffer
;;          (rel-file-name (file-relative-name buffer-file-name target-dir))

;;          ;; THE SINGLE RULE: If the minor mode function exists, turn it on
;;          (mode-activation-rule '(eval . (when (fboundp 'org-history-mode)
;;                                           (org-history-mode 1))))

;;          ;; Read file if it exists, otherwise start with a clean nil list
;;          (config (and (file-exists-p file-path)
;;                       (with-temp-buffer
;;                         (insert-file-contents file-path)
;;                         (ignore-errors (read (current-buffer)))))))

;;     ;; Update the file-specific section with our single evaluation rule
;;     (unless (member mode-activation-rule (cdr (assoc rel-file-name config #'equal)))
;;       (setf (alist-get rel-file-name config nil nil #'equal)
;;             (cons mode-activation-rule (cdr (assoc rel-file-name config #'equal)))))

;;     ;; Write it back out cleanly
;;     (with-temp-file file-path
;;       (let (print-level print-length)
;;         (pp config (current-buffer))))
;;     (message "Successfully configured .dir-locals.el to activate org-history for %s" rel-file-name)
;;     file-path))

(defun org-history--append-after-save-to-dir-locals (target-dir)
  "Safely add or merge a file-specific activation rule into TARGET-DIR/.dir-locals.el.
This activates `org-history-mode' (or your specific minor mode) ONLY when
the current file is opened.
Return .dir-locals.el path."
  (interactive "DSelect directory for .dir-locals.el: ")
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))

  (let* ((target-dir (expand-file-name (or target-dir default-directory)))
         (file-path (expand-file-name ".dir-locals.el" target-dir))
         ;; Calculate the relative file name for the current buffer
         (rel-file-name (file-relative-name buffer-file-name target-dir))

         ;; THE SINGLE RULE: If the minor mode function exists, turn it on
         (mode-activation-rule '(eval . (if (fboundp 'org-history-mode)
                                          (org-history-mode 1))))

         ;; Read file if it exists, otherwise start with a clean nil list
         (config (and (file-exists-p file-path)
                      (with-temp-buffer
                        (insert-file-contents file-path)
                        (ignore-errors (read (current-buffer)))))))

    ;; Update the file-specific section with our single evaluation rule
    (unless (member mode-activation-rule (cdr (assoc rel-file-name config #'equal)))
      (setf (alist-get rel-file-name config nil nil #'equal)
            (cons mode-activation-rule (cdr (assoc rel-file-name config #'equal)))))

    ;; (unless (member mode-activation-rule (cdr (assoc rel-file-name config #'equal)))
    ;;   (setf (alist-get rel-file-name config)
    ;;         (cons mode-activation-rule (cdr (assoc rel-file-name config)))))

    ;; Write it back out cleanly
    (with-temp-file file-path
      (let (print-level print-length)
        (pp config (current-buffer))))
    (message "Successfully configured .dir-locals.el to activate org-history for %s" rel-file-name)
    file-path))

(defun org-history--append-after-save-to-dir-locals (target-dir)
  "Safely add or merge the local after-save-hook into TARGET-DIR/.dir-locals.el.
Add: function to `after-save-hook' globally for org-mode, but enable
`org-history-track-file' only for the current `buffer-file-name' relative
to the project directory.
Return .dir-locals.el path."
  (interactive "DSelect directory for .dir-locals.el: ")
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (let* ((target-dir (expand-file-name (or target-dir default-directory)))
         (file-path (expand-file-name ".dir-locals.el" target-dir))
         ;; 1. Calculate the relative file name at configuration time
         (rel-file-name (file-relative-name buffer-file-name target-dir))

         ;; FIXED: Calculate the relative name of the buffer dynamically at runtime
         ;; against `default-directory` (which points to the .dir-locals.el location)
         (new-rule `(eval . (when (and (fboundp 'org-history-mode)
                                       buffer-file-name
                                       (string-equal (file-relative-name buffer-file-name default-directory)
                                                     ,rel-file-name))
                              (org-history-mode 1))))

         ;; Read file if it exists, otherwise start with a clean nil list
         (config (and (file-exists-p file-path)
                      (with-temp-buffer
                        (insert-file-contents file-path)
                        (ignore-errors (read (current-buffer)))))))

    ;; 2. Update the general 'org-mode section for the hook
    (unless (member new-rule (cdr (assoc 'org-mode config)))
      (setf (alist-get 'org-mode config) (cons new-rule (cdr (assoc 'org-mode config)))))

    ;; 4. Write it back out cleanly
    (with-temp-file file-path
      (let (print-level print-length)
        (pp config (current-buffer))))
    (message "Successfully synchronized .dir-locals.el for %s" rel-file-name)
    file-path))






;; -=-= hook: after-save

(defun org-history-hook-for-after-save ()
  "Automatically commit or amend in Git after saving a buffer.
Intended for `after-save-hook'.

If there is no .git or no commits or previous commit was not starting
 with \"org-history\" string, we ask user to confirm to commit and
 remember choice in current buffer in `org-history-track-file' variable.
We ue `y-or-n-p' to ask user at init repo and at new commit it
 `org-history-track-file' was not set.
"
  (org-history--debug "org-history-hook-for-after-save N1")
  (when-let ((dir (when buffer-file-name (file-name-directory buffer-file-name))) ; root of current file ; if buffer visiting a file
             ;; if hook-placed is local we
             (hook-placed (org-history--check-hook-scope 'after-save-hook #'org-history-hook-for-after-save)))
    (org-history--debug "org-history-hook-for-after-save N2")
    ;; Check if we configured correctly for current directory or local buffer
    (when (or (eq hook-placed :local)
              (eq hook-placed :both)
              (and (eq hook-placed :global)
                   (catch 'found
                     (dolist (path org-history-directories)
                       (when (file-equal-p dir path)
                         (throw 'found t)))
                     nil)))
      (org-history--debug "org-history-hook-for-after-save N3" default-directory (vc-git-root buffer-file-name) buffer-file-name)
      (org-history--vc-reset-cache)
      (org-history--vc-reset-cache buffer-file-name)


      (let ((backend (vc-backend buffer-file-name))
            ;; works for not added files too:
            (default-directory (vc-git-root buffer-file-name)))  ; root of .git or nil to check if .git exist.


        ;; Safety check: Ensure the buffer is visiting a file and it's backed by Git
        ;; when file is not registered and not bound to other VCS
        ;; when
        (when (and (or (not backend) (eq backend 'Git))

                   ;; 1. Check if the directory is NOT in Git, and ask the user to initialize it
                   ;; (print (list is-git backend  default-directory))
                   (not default-directory))
          (if (y-or-n-p (format "org-history: Do git init in %s? " dir))
              (progn
                (setq default-directory dir) ; restore
                (vc-file-clearprops buffer-file-name)
                ;; Initialize the repository synchronously
                (org-history-git-init (file-relative-name buffer-file-name)) ; Uses default-directory, set org-history-track-file to 'track-this-file

                ;; Update our state flag since it's now a Git repo
                (setq backend 'Git)

                (message "Initialized empty Git repository in %s" dir))
            ;; else If user says no, we display a silent message and do nothing
            (message "Skipped Git auto-commit (Directory is not a Git repository).")))

        (org-history--debug "org-history-hook-for-after-save N32" default-directory backend)
        (when default-directory ; if default-directory is not nil, it is 'Git
          (org-history--debug "org-history-hook-for-after-save N4 %s" default-directory buffer-file-name (vc-backend buffer-file-name))
          ;; (rev (vc-working-revision nil backend)) ; working or last revision
          (let* (;; "Get the YYYY-MM-DD author date for a specific REV hash of FILE."
                 (last-commit-date (org-history--vc-git-get-last-commit-date))
                 (last-commit-message (when last-commit-date
                                        (string-trim (vc-git--run-command-string nil "log" "-1" "--pretty=%B"))))
                 ;; (last-commit-date   (let ((default-directory dir)) ; required?
                 ;;                       (with-temp-buffer
                 ;;                         ;; 't' makes this synchronous so the buffer fills before we read it
                 ;;                         (vc-git-command (current-buffer) 0 nil
                 ;;                                         "show" "-s" "--format=%as" rev)
                 ;;                         (string-trim (buffer-string)))))

                 ;; Fetch the current system date (dynamically testable via mocking)
                 (current-date (format-time-string "%Y-%m-%d")))

            ;; Stage the saved file
            ;; (vc-git-command nil 0 file-relative "add")


            ;; "Commit": with --amend (same date) or without (new day, no previous)
            ;; (print (list rev last-commit-date current-date))
            (if (and last-commit-date
                     (string-equal last-commit-date current-date)
                     (string-prefix-p "org-history" last-commit-message))
                ;; Case 1: Same day -> Amend without altering the commit message
                (progn
                  (org-history--debug "org-history-hook-for-after-save N5")
                  (org-history--vc-add-file buffer-file-name 'Git)
                  (vc-git-command nil 0 nil "commit" "--amend" "--no-edit" "--date=now")
                  (setq org-history-track-file 'track-file) ; dont ask next time if user made custom commit.
                  (message "VC-Git: Amended existing commit for today."))

              ;; else: Case 2: New day OR fresh repo -> Create a new commit with an empty message
              ;; Initilize .git if it have no commits.
              (when (eq org-history-track-file nil)
                (if (if last-commit-date
                          (y-or-n-p (format "org-history: enable auto-commit on save this? " (file-relative-name buffer-file-name)))
                        ;; else
                        (y-or-n-p (format "org-history: Do git init in %s? " dir)))
                  (setq org-history-track-file 'track-file)
                  ;; else
                  (setq org-history-track-file 'dont-track-file)))

              (when (eq org-history-track-file 'track-file)
                ;; initialize .git if it have no commits
                (unless last-commit-date ; is nil, no commits at all, git probably is not initialized
                  (dolist (args org-history-git-init-commands)
                    (apply #'vc-git-command nil 0 nil args))) ; 'apply' lets us unpack the 'args' list directly into the function call

                (org-history--debug "org-history-hook-for-after-save N6")
                (org-history--vc-add-file buffer-file-name 'Git)
                (vc-git-command nil 0 nil "commit" "--allow-empty-message" "-m" "org-history")
                (org-history--debug "org-history-hook-for-after-save N7" (shell-command-to-string "git rev-list --count HEAD") last-commit-date current-date)

                ;; (vc-checkin (list file) backend comment)
                (message "VC-Git: Created new empty-message commit.")
                ;; end of "Commit"
                ))

            ;; Performance Sync: Clear VC internal properties so the UI/modeline updates immediately
            (vc-file-clearprops buffer-file-name)))))))

;; Register the hook globally to trigger upon buffer saves
;; (add-hook 'after-save-hook #'org-history-hook-for-after-save)
;; (remove-hook 'after-save-hook #'org-history-hook-for-after-save)

;; -=-= function: headers folding

(defun org-history--at-unfold-add-date (orig-fun &rest args)
  "Triggered after org-cycle. Checks if user interactively unfolded a heading.
Reliably check for interactive execution using :around advice."
  ;; 1. Check interactivity FIRST while org-cycle is at the top of the stack
  (let ((interactive-call (called-interactively-p 'any))
        (hook-placed (org-history--check-hook-scope 'after-save-hook #'org-history-hook-for-after-save)))

    ;; 2. Run the original org-cycle command so the heading actually changes state
    (apply orig-fun args)

    ;; 3. Now perform your post-execution visibility checks safely
  (when (and interactive-call			; 1. Only run if called interactively
             (org-at-heading-p)		; 2. Only run if cursor is on a heading
             (not (save-excursion		; 3. Ensure heading is currently open
                    (end-of-line)
                    (org-fold-folded-p nil 'headline)))
             (or (eq hook-placed :local)
                 (eq hook-placed :both)
                 (and (eq hook-placed :global)
                      (catch 'found
                        (dolist (path org-history-directories)
                          (when (file-equal-p dir path)
                            (throw 'found t)))
                        nil))))
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (org-end-of-subtree t t) (point))))
      (org-history-outline--add-dates start end))
    ;; (message "Interactively unfolded heading!")
    )))

;; Attach as an ':after' advice to org-cycle

;; -=-= minor mode

(define-minor-mode org-history-mode
  "Minor mode for `org-mode' to showing date of last modified per outlier."
  :init-value nil
  ;; :keymap oai-mode-map
  :group 'org-nistory
  (unless (derived-mode-p 'org-mode)
    (user-error "org-history minor mode failed to activate in buffer %s, not Org mode" (buffer-name (current-buffer))))
  (if org-history-mode
      (progn
        (org-history-outline--add-dates)
        (add-hook 'after-save-hook #'org-history-hook-for-after-save nil t)
        (advice-add 'org-cycle :around #'org-history--at-unfold-add-date '((local . t))))
    ;; else - off
    (advice-remove 'org-cycle #'org-history--at-unfold-add-date)
    (remove-hook 'after-save-hook #'org-history-hook-for-after-save t)
    (org-history-outline-clear-all-org-date-overlays)

    (kill-local-variable 'org-history-track-file)))

;; Optimization: Only trigger if Emacs VC explicitly sees the file as 'edited
      ;; (when (eq (vc-state buffer-file-name) 'edited)


;; (defun org-history-hook-for-after-save ()
;;   "Automatically commit or amend in Git after saving a buffer.
;; Utilizes the Emacs VC package for state tracking and handles empty repos smoothly."
;;   (when (and buffer-file-name
;;              (eq (vc-backend buffer-file-name) 'Git))
;;     (let* ((default-directory (file-name-directory buffer-file-name))
;;            (file-relative (file-relative-name buffer-file-name))

;;            ;; 1. Check if buffer is actually modified before doing heavy Git lifting
;;            (is-modified (buffer-modified-p))

;;            ;; 2. Verify if HEAD exists safely
;;            (has-commits (zerop (call-process "git" nil nil nil "rev-parse" "--verify" "HEAD" "2>/dev/null")))

;;            ;; 3. Fetch the last commit date using vc-git-command structure for speed
;;            (last-commit-date (when has-commits
;;                                (with-temp-buffer
;;                                  (vc-git-command (current-buffer) 0 nil "log" "-1" "--format=%as")
;;                                  (string-trim (buffer-string)))))

;;            (current-date (format-time-string "%Y-%m-%d")))

;;       ;; Execute only if the buffer actually contains new modifications
;;       (when is-modified

;;         ;; Stage the saved file
;;         (vc-git-command nil 0 file-relative "add")

;;         ;; Debugging print statement as requested
;;         (print (list :last-date last-commit-date :current-date current-date))

;;         (if (and has-commits (string-equal last-commit-date current-date))
;;             ;; Case 1: Same day -> Amend
;;             (progn
;;               (vc-git-command nil 0 nil "commit" "--amend" "--no-edit")
;;               (message "VC-Git: Amended existing commit for today."))
;;           ;; Case 2: New day OR fresh repo -> New commit
;;           (progn
;;             (vc-git-command nil 0 nil "commit" "--allow-empty-message" "-m" "")
;;             (message "VC-Git: Created new empty-message commit.")))

;;         ;; Sync Emacs VC UI state
;;         (vc-file-clearprops buffer-file-name)))))

;; ;; Switch to 'before-save-hook' so we capture state BEFORE Emacs flushes
;; ;; the buffer and resets file status indicators.
;; (add-hook 'before-save-hook #'org-history-hook-for-after-save)
;; (remove-hook 'before-save-hook #'org-history-hook-for-after-save)
;;; provide

(provide 'org-history)

;;; org-history.el ends here
