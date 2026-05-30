;;; org-history.el --- Dates for org-mode headers from git, minor mode or global hook -*- lexical-binding: t; -*-

;;; Commentary:

;; Check if file is tracked:
;; (vc-backend buffer-file-name)

;; Check if there is .git
;; (vc-git-root buffer-file-name)

;; TODO:
;; - check if last commit have "org-history at begining" and if not ask whether to commit and remember answer. clear steate at switching off and on mode.
;; - check if .git already exist
;; - mouseover notification for Org header
;; - list of folders
;; - command to add current folder to list
;; - check if .gitignore is not exist already
;; - test with modifying of two files

;;; Code:

(require 'vc)
(require 'vc-git)
(require 'org-history-debug)

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
  "List of directories used with org-history."
  :type 'string
  :group 'org-history)


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
    (vc-working-revision (vc-root-dir) (or backend 'Git))))

(defun org-history--vc-git-get-last-commit-date ()
  "Return string with the last commit date or nil.
Uses `default-derectory'."
  (when-let ((rev (org-history--vc-get-last-commit 'Git)))
    (with-temp-buffer
      ;; 't' makes this synchronous so the buffer fills before we read it
      (vc-git-command (current-buffer) 0 nil
                      "show" "-s" "--format=%as" rev)
      (string-trim (buffer-string)))))

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

    ;; Commit is not required, add is enough
    (message "Registered .gitignore and %s with Git!" default-directory)))


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


(defun org-history--append-after-save-to-dir-locals (target-dir)
  "Safely add or merge the local after-save-hook into TARGET-DIR/.dir-locals.el.
Return .dir-locals.el path."
  (interactive "DSelect directory for .dir-locals.el: ")
  (let* ((file-path (expand-file-name ".dir-locals.el" (or target-dir default-directory)))
         ;; FIX: Updated to inject the safe check and warning message
         (new-rule '(eval . (if (fboundp 'org-history-commit-on-save-hook)
                                (add-hook 'after-save-hook #'org-history-commit-on-save-hook nil t)
                              (lwarn 'org-history :warning "`org-history` is not available; auto-commit on save disabled."))))
         ;; 1. Read file if it exists, otherwise start with a clean nil list
         (config (and (file-exists-p file-path)
                      (with-temp-buffer
                        (insert-file-contents file-path)
                        (ignore-errors (read (current-buffer)))))))

    ;; 2. Seamlessly update or create the 'org-mode section
    (unless (member new-rule (cdr (assoc 'org-mode config)))
      (setf (alist-get 'org-mode config) (cons new-rule (cdr (assoc 'org-mode config)))))

    ;; 3. Write it back out cleanly
    (with-temp-file file-path
      (let (print-level print-length)
        (pp config (current-buffer))))
    (message "Successfully synchronized .dir-locals.el")
    file-path))


(defun org-history-commit-on-save-hook ()
  "Automatically commit or amend in Git after saving a buffer.
Intended for `after-save-hook'.
Utilizes the Emacs VC package for state tracking and handles empty repos smoothly."
  (org-history--debug "org-history-commit-on-save-hook N1")
  (when-let ((dir (when buffer-file-name (file-name-directory buffer-file-name))) ; root of current file ; if buffer visiting a file
             ;; if hook-placed is local we
             (hook-placed (org-history--check-hook-scope 'after-save-hook #'org-history-commit-on-save-hook)))
    (org-history--debug "org-history-commit-on-save-hook N2")
    ;; Check if we configured correctly for current directory or local buffer
    (when (or (eq hook-placed :local)
              (eq hook-placed :both)
              (and (eq hook-placed :global)
                   (catch 'found
                     (dolist (path org-history-directories)
                       (when (file-equal-p dir path)
                         (throw 'found t)))
                     nil)))
      (org-history--debug "org-history-commit-on-save-hook N3" default-directory (vc-git-root buffer-file-name) buffer-file-name)
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
          (if (y-or-n-p (format "Maybe init git in directory %s? " dir))
              (progn
                (setq default-directory dir) ; restore
                (vc-file-clearprops buffer-file-name)
                ;; Initialize the repository synchronously
                (org-history-git-init (file-relative-name buffer-file-name)) ; Uses default-directory)

                ;; Update our state flag since it's now a Git repo
                (setq backend 'Git)

                (message "Initialized empty Git repository in %s" dir))
            ;; else If user says no, we display a silent message and do nothing
            (message "Skipped Git auto-commit (Directory is not a Git repository).")))

        (org-history--debug "org-history-commit-on-save-hook N32" default-directory backend)
        (when default-directory ; if default-directory is not nil, it is 'Git
          (org-history--debug "org-history-commit-on-save-hook N4 %s" default-directory buffer-file-name (vc-backend buffer-file-name))
          ;; (rev (vc-working-revision nil backend)) ; working or last revision
          (let* (;; "Get the YYYY-MM-DD author date for a specific REV hash of FILE."
                 (last-commit-date (org-history--vc-git-get-last-commit-date))
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
            (org-history--vc-add-file buffer-file-name 'Git)

            ;; Decision Matrix: Amend or New Commit?
            ;; (print (list rev last-commit-date current-date))
            (if (and last-commit-date (string-equal last-commit-date current-date))
                ;; Case 1: Same day -> Amend without altering the commit message
                (progn
                  (org-history--debug "org-history-commit-on-save-hook N5")
                  (vc-git-command nil 0 nil "commit" "--amend" "--no-edit" "--allow-empty-message")
                  (message "VC-Git: Amended existing commit for today."))

              ;; else: Case 2: New day OR fresh repo -> Create a new commit with an empty message
              (unless last-commit-date ; is nil, no commits at all, git probably is not initialized
                (dolist (args org-history-git-init-commands)
                  ;; 'apply' lets us unpack the 'args' list directly into the function call
                  (apply #'vc-git-command nil 0 nil args)))
              (org-history--debug "org-history-commit-on-save-hook N6")
              (vc-git-command nil 0 nil "commit" "--allow-empty-message" "-m" "")
              (org-history--debug "org-history-commit-on-save-hook N7" (shell-command-to-string "git rev-list --count HEAD") last-commit-date current-date)
              ;; (vc-checkin (list file) backend comment)
              (message "VC-Git: Created new empty-message commit."))

            ;; Performance Sync: Clear VC internal properties so the UI/modeline updates immediately
            (vc-file-clearprops buffer-file-name)))))))

;; Register the hook globally to trigger upon buffer saves
;; (add-hook 'after-save-hook #'org-history-commit-on-save-hook)
;; (remove-hook 'after-save-hook #'org-history-commit-on-save-hook)

(define-minor-mode org-history
  "Minor mode for `org-mode' to showing date of last modified per outlier."
  :init-value nil
  ;; :keymap oai-mode-map
  :group 'org-nistory
  (unless (derived-mode-p 'org-mode)
    (user-error "org-history minor mode failed to activate in buffer %s, not Org mode" (buffer-name (current-buffer))))
  (if org-history
      (add-hook 'after-save-hook #'org-history-commit-on-save-hook nil t)
    ;; else - off
    (remove-hook 'after-save-hook #'org-history-commit-on-save-hook t)))

;; Optimization: Only trigger if Emacs VC explicitly sees the file as 'edited
      ;; (when (eq (vc-state buffer-file-name) 'edited)


;; (defun org-history-commit-on-save-hook ()
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
;; (add-hook 'before-save-hook #'org-history-commit-on-save-hook)
;; (remove-hook 'before-save-hook #'org-history-commit-on-save-hook)

(provide 'org-history)

;;; org-history.el ends here
