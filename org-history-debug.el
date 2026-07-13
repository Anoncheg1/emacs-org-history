;;; org-history-debug.el --- Debug in separate buffer if enabled-*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>
;; URL: https://codeberg.org/Anoncheg/emacs-org-history

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

;; Check if file is tracked:
;; (vc-backend buffer-file-name)

;; Check if there is .git
;; (vc-git-root buffer-file-name)

;;; Code:

(require 'vc)
(require 'vc-git)

(defgroup org-history-debug nil
  "Faces for OAI blocks."
  :tag "Org dates for outlines"
  :group 'org-history)

(defcustom org-history-debug-buffer nil
  "If non-nil, enable debugging to a new buffer with such name.
Set to something like \"*debug-history*\"  to enable debugging."
  :type '(choice (const :tag "No debugging" nil)
                 (string :tag "Name of buffer"))
  :group 'org-history-debug)

(defcustom org-history-debug-ert-enabled nil
  "Non-nil means use stdout instead of separate buffer for debugging.
useful for debugging in ERT."
  :type 'boolean
  :group 'org-history-debug)

(defcustom org-history-debug-timestamp-flag t
  "Non-nil means add timestamp to every debug message."
  :type 'boolean
  :group 'org-history-debug)

(defcustom org-history-debug-filter nil
  "If non-nil output only strings that contains this string."
  :type '(choice (const :tag "No filter" nil)
                 (string :tag "Regex string for filter"))
  :group 'org-history-debug)

(defun org-history-debug--format-argument (args)
  "Convert ARGS to a string.
ARGS may be any Elisp object.
Used to prepare arguments of `oai--debug' for output by converting to a
string.
Always return string."
  (if (equal (type-of args) 'string)
      (format "%s\n" args)
    (concat (prin1-to-string args) "\n")))

(defun org-history-debug--safe-format (fmt &rest args)
  "Format with fixing count of '%s' in FMT according to length of ARGS.
Formats by removing all '%s' from FMT and appending ' %s' for each ARGS."
  ;; Remove all "%s" from fmt
  (let* ((fmt (replace-regexp-in-string " ?%s" "" fmt))
         (num-args (length args))
         (fmt (concat fmt " "
                   (string-join (make-list num-args "%s") " ")
                   "\n")))
    (apply #'format fmt args)))



(defun org-history-debug-print (&rest args)
  "If first argument of ARGS is a stringwith %s than behave like format.
Otherwise format every to string and concatenate.
Return last argument, but should not be used for return value."
  (when (and (or org-history-debug-buffer
                 (bound-and-true-p org-history-debug-ert-enabled))
             args)

    (save-excursion
      (let* ((buf-exist (and org-history-debug-buffer (get-buffer org-history-debug-buffer)))
             (bu (or buf-exist
                     (and (bound-and-true-p org-history-debug-ert-enabled) (current-buffer))
                     (get-buffer-create org-history-debug-buffer)))
             (current-window (selected-window))
             (bu-window (or (get-buffer-window bu)
                            (when (not (eq last-input-event 7)) ; not C-g exit - too much verbose
                              (let ((w-width (if (>= (count-windows) 2)
                                                0.2
                                              0.33)))
                                (display-buffer-in-direction
                                 bu
                                 (list (cons 'direction 'left)
                                       (cons 'window 'new)
                                       (cons 'window-width w-width)))))
                            (when (not (eq last-input-event 7)) ; not C-g exit - too much verbose
                              (select-window current-window) ; return nil
                              t)))
             (timestamp (when org-history-debug-timestamp-flag
                          (format-time-string "%M:%S.%3N " (current-time))))
             result-string)

        (with-current-buffer bu
          ;; - 1) move point to  to bottom
          (when buf-exist ; was not created
              (goto-char (point-max))
            ;; else buffer just created
            (local-set-key "q" #'quit-window))
           ;; - scroll debug buffer down
          (when (and bu-window (not (bound-and-true-p org-history-debug-ert-enabled)))
              (with-selected-window (get-buffer-window bu)
                   (goto-char (point-max))))
          ;; ;; - output caller function ( working, but too heavy)
          ;; (let ((caller
          ;;        (org-history-debug--get-caller)))
          ;;   (when caller
          ;;     (insert "Din ")
          ;;     (insert caller)
          ;;     (insert " :")))
          ;; - 2) prepare output in result-string variable
          (save-match-data
            ;; if first line is a string with %s we output all at one line
            (if (and (equal (type-of (car args)) 'string)
                     (string-match "%s" (car args)))
                ;; "safe format"
                (setq result-string (apply #'org-history-debug--safe-format args)) ; (concat (apply #'format (car args) (cdr args)) "\n"))

              ;; else - "```debug" with line by line
              (setq result-string (concat (org-history-debug--format-argument (car args))
                                          (when (cdr args)
                                            (concat
                                             "```debug\n" (apply #'concat (mapcar #'org-history-debug--format-argument
                                                                               (cdr args)))
                                             "```\n")))))
            (when (and org-history-debug-filter
                       (not (string-match-p (regexp-quote org-history-debug-filter) result-string)))
                    (setq result-string nil))
            ;; - 3) output as: timestamp - function - ```debug or "safe-format"
            (when result-string
              ;; - two ways to output: for ert.el and to debug buffer.
              (if (bound-and-true-p org-history-debug-ert-enabled)
                  (princ (concat timestamp result-string "\n"))
                ;; else
                ;; first word insert as a link
                (when timestamp (insert timestamp))
                (if (string-match "[\s\n]+" result-string)
                    (let ((first-part (substring result-string 0 (match-beginning 0)))
                          (second-part (substring result-string (match-beginning 0))))
                        (insert-text-button first-part
                                            'type 'help-function-def
                                            'help-args (list (intern first-part) nil))
                        (insert second-part))
                    ;; else - as one
                    (insert result-string)))))))))
  (car (last args)))

(defun org-history-debug--vc-git-status ()
  "Return git status string."
  (let ((buf-name " *git-status-temp*")) ; Leading space hides buffer from list
    (if (eq (vc-responsible-backend default-directory) 'Git)
        (let (output)
          (vc-git-command (get-buffer-create buf-name) 0 nil "status" "--short")
          (with-current-buffer buf-name
            (setq output (buffer-string))
            (if (string-empty-p (string-trim output))
                (setq output "Working tree clean.")
              ;; else
              ;; (print (list "wtf2" (format "--- Git Status ---\n%s" output)))
              ;; Using "%s" ensures newlines are respected in the *Messages* buffer
              (setq output (format "--- Git Status ---\n%s" output))))
          (kill-buffer buf-name)
          output)
      "Not a Git repository.")))


(defun org-history-debug--vc-git-log-to-messages ()
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


(provide 'org-history-debug)

;;; org-history-debug.el ends here
