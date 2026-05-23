(require 'vc-git)
(require 'subr-x)

;; TODO:
;; - mouseover notification for Org header
;; - list of folders
;; - command to add current folder to list
;; - check if .gitignore is not exist already
;; - test with modifying of two files

(defcustom org-history-git-init-commands
  '(("init") ; git init
    ("config" "user.name" "'(none)'") ; git config user.name '(none)'
    ("config" "user.email" "''")) ; git config user.email ''
  "List of argument lists passed to `vc-git-command` during initialization."
  :type '(repeat (repeat string))
  :group 'vc)

(defcustom gitignore-content '("*.elc"
                               "*~"
                               "#*#"
                               "/.emacs.desktop"
                               "/.emacs.desktop.lock"
                               "elpa/")
  "List of default patterns to write into a new .gitignore file.
Ignores: compiled files, backups, and lock files."
  :type '(repeat string)
  :group 'my-git-tools)

(defun org-history-git-init ()
  "Execute the custom Git initialization commands sequentially.
Use `default-directory'."
  (interactive)
  ;; Step 1: Create the .gitignore file safely
  ;; (we need at leas one file init initialize)
  ;; (print (list "def dir:" default-directory))
  (let ((gitignore-file (expand-file-name ".gitignore" default-directory))) ; default-directory may be nil

    (with-temp-file gitignore-file
      (insert (mapconcat 'identity gitignore-content "\n") "\n")
      (write-file gitignore-file))
    (message "Created .gitignore...")

    ;; Step 1: Initialize the Git repository
    (dolist (args org-history-git-init-commands)
      ;; 'apply' lets us unpack the 'args' list directly into the function call
      (apply #'vc-git-command nil 0 nil args))
    (message "Initialized Git repository...")

    ;; Step 2: Clear Emacs VC cache so it realizes Git now exists
    (vc-file-clearprops gitignore-file)

    ;; Step 3: Commit first file to finish initialization
    (vc-register (list 'Git (list gitignore-file)))
    ;; Commit is not required, add is enough
    (message "Registered .gitignore and %s with Git!" default-directory)))

(defun org-history-commit-on-save-hook ()
  "Automatically commit or amend in Git after saving a buffer.
Utilizes the Emacs VC package for state tracking and handles empty repos smoothly."
  ;; Safety check: Ensure the buffer is visiting a file and it's backed by Git
  (when buffer-file-name
    (let* ((dir (file-name-directory buffer-file-name)) ; root of current file
           (file-relative (file-relative-name buffer-file-name)) ; name of file, Use default-directory
           (backend (vc-backend buffer-file-name))
           ;; Check if this file or any parent directory is already tracked by Git
           (is-git (eq backend 'Git))
           (default-directory (vc-git-root buffer-file-name)) ; root of .git
           )
      (when (or (not backend) (eq backend 'Git)) ; when file is not registered and not bound to other VCS

      ;; 1. Check if the directory is NOT in Git, and ask the user to initialize it
      ;; (print (list is-git backend  default-directory))
      (if (not default-directory)
        (when (y-or-n-p (format "Maybe init git in directory %s? " dir))
          (setq default-directory dir)
          ;; Initialize the repository synchronously
          (org-history-git-init)

          ;; Force Emacs VC to register the file so it acknowledges the new repository
          (vc-file-clearprops buffer-file-name)
          (vc-register (list 'Git (list buffer-file-name)))
          ;; Update our state flag since it's now a Git repo
          (setq is-git t)
          (setq backend 'Git)
          (setq default-directory (vc-git-root buffer-file-name))
          (message "Initialized empty Git repository in %s" dir))
        ;; else If user says no, we display a silent message and do nothing
        (message "Skipped Git auto-commit (Directory is not a Git repository).")))


      (let* ((rev (vc-working-revision buffer-file-name backend)) ; working or last revision

            ;; "Get the YYYY-MM-DD author date for a specific REV hash of FILE."
            (last-commit-date (when rev
                                (let ((default-directory (file-name-directory buffer-file-name)))
                                  (with-temp-buffer
                                    ;; 't' makes this synchronous so the buffer fills before we read it
                                    (vc-git-command (current-buffer) 0 nil
                                                    "show" "-s" "--format=%as" rev)
                                    (string-trim (buffer-string))))))

            ;; Fetch the current system date (dynamically testable via mocking)
            (current-date (format-time-string "%Y-%m-%d")))

        ;; Stage the saved file
        (vc-git-command nil 0 file-relative "add")

        ;; Decision Matrix: Amend or New Commit?
        ;; (print (list rev last-commit-date current-date))
        (if (and rev (string-equal last-commit-date current-date))
            ;; Case 1: Same day -> Amend without altering the commit message
            (progn
              (vc-git-command nil 0 nil "commit" "--amend" "--no-edit" "--allow-empty-message")
              (message "VC-Git: Amended existing commit for today."))

          ;; Case 2: New day OR fresh repo -> Create a new commit with an empty message
          (progn
            (vc-git-command nil 0 nil "commit" "--allow-empty-message" "-m" "")
            (message "VC-Git: Created new empty-message commit.")))

        ;; Performance Sync: Clear VC internal properties so the UI/modeline updates immediately
        (vc-file-clearprops buffer-file-name)))))

;; Optimization: Only trigger if Emacs VC explicitly sees the file as 'edited
      ;; (when (eq (vc-state buffer-file-name) 'edited)

;; Register the hook globally to trigger upon buffer saves
;;
;; (add-hook 'after-save-hook #'org-history-commit-on-save-hook)
;; (remove-hook 'after-save-hook #'org-history-commit-on-save-hook)

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
