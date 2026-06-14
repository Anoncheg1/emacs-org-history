;;; org-history-outline.el --- Attach dates at the end of Org outlines -*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>
;; URL: https://codeberg.org/Anoncheg/emacs-org-history
;; Version: 0.2
;; Package-Requires: ((emacs "29.1"))

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

;; To get date use `org-history--vc-git-get-range-last-mod-date'.

;;; Code:

(require 'color)

;; -=-= variables
(defcustom org-history-outline-max-days (* 360 2)
  "Maximum number of days to keep in the outline history.
This value must be an integer representing the day retention threshold.
Used to color range for dates, adjusted to oldest commit date in repo."
  :group 'org-history
  :type 'integer
  :local t
  :safe #'integerp)

(defcustom org-history-outline-min-days 90
  "Minimum number of days to keep in the outline history.
This value must be an integer representing the day retention threshold.
Used to calculate max-days range for colors of dates."
  :group 'org-history
  :type 'integer
  :safe #'integerp)

(defcustom org-history-outline-date-column 60
  "Column to put date at."
  :group 'org-history
  :type 'integer
  :safe #'integerp)

;; -=-= Attach overlay
(defun org-history-outline--outline-attach-date (date-str)
  "Attach overlay with date at the end header with color gradient.
Cursors should be at header position.
DATE-STR is in form of YYYY-MM-DD.
Smooth `vc-annotate' color gradient is used by how old date is.
Overlay is not modifiable and dont modify buffer content.
Automatically deletes older date overlays on the same headline when
 updated."
  ;; (interactive "sEnter date (YYYY-MM-DD): ")
  (let* ((time-attr (condition-case nil
                        (date-to-time date-str)
                      (error (user-error "Invalid date format! Use YYYY-MM-DD"))))
         ;; 1. Max out at 0 to avoid future negative date math bugs safely in one line
         (days-old (max 0 (floor (- (float-time) (float-time time-attr)) 86400)))
         ;; 2. Generate smooth vc-annotate aging color wheel
         (ratio (/ (min days-old org-history-outline-max-days) (float org-history-outline-max-days)))
         (hue (* ratio 0.66)) ; 0.0 = Red, 0.66 = Blue
         (rgb (color-hsl-to-rgb hue 0.8 0.5))
         (color-hex (apply #'color-rgb-to-hex rgb))

         ;; --- THE CHARACTER CALCULATION SETUP ---
         (lend (line-end-position))
         (lstart (1- lend))
         ;; (target-column 60)

         ;; Calculate the current text column width manually
         (current-line-length (- lend (line-beginning-position)))
         ;; Determine needed padding (fallback to at least 2 spaces if line is longer than target)
         (padding-needed (max 2 (- org-history-outline-date-column current-line-length)))
         ;; Generate a real string containing exactly that many spaces
         (calculated-spaces (make-string padding-needed ?\s)))

    ;; 3. CLEANUP: Clear overlays sitting exactly on that last character slot
    (remove-overlays lstart lend 'identity 'my-org-date)

    ;; 4. CREATION: Render using calculated hard padding strings
    (let* ((ov (make-overlay lstart lend))
           (last-char (buffer-substring-no-properties lstart lend))
           (date-text (propertize (format "[%s]" date-str)
                                  'face `(:foreground ,color-hex :weight bold)
                                  'help-echo (format "Age: %d days old" days-old)
                                  'read-only t
                                  'intangible t
                                  'cursor-intangible t)))

      (overlay-put ov 'identity 'my-org-date)
      (overlay-put ov 'priority 100)

      ;; Concatenate the last character, the exact computed spaces, and the date.
      ;; No complex `:align-to` layout engines involved—just pure text math.
      (overlay-put ov 'display (concat last-char calculated-spaces date-text)))))


(defun org-history-outline-clear-all-org-date-overlays ()
  "Instantly remove all custom date overlays from the entire buffer."
  (interactive)
  (remove-overlays (point-min) (point-max) 'identity 'my-org-date)
  (font-lock-flush)
  (message "Successfully cleared all header date overlays."))

;; -=-= Attach-date
(defun org-history-outline-add-dates (&optional page-beg page-end)
  "Collect line ranges for visible Org headings and apply dates separately.
Optional arguments PAGE-BEG PAGE-END are position in current buffer."
  (interactive)
  (org-history-debug-print "org-history-outline-add-dates %s %s" page-beg page-end)
  ;; if not checked that commit exist error: gethash(4 nil) error in `org-history-outline--process-tasks'
    (let (tasks)
      (save-excursion
        (goto-char (or page-beg (point-min)))
        ;; Ensure we start at the first heading
        (unless (org-at-heading-p)
          (outline-next-heading))

        ;; PHASE 1: Collect coordinates without touching Git or overlays
        (while (and (not (eobp))
                    (if page-end (< (point) page-end) t))
          (unless (org-fold-core-get-folding-spec 'headline (point))
            (let* ((heading-pos (point))
                   (start (save-excursion (forward-line 1) (line-number-at-pos)))
                   (end (save-excursion (org-end-of-subtree t t) (line-number-at-pos)))
                   (real-start (min start end))
                   (real-end (max start end)))
              ;; Push a task tuple: (heading-marker start-line end-line)
              ;; Using a marker ensures the position stays accurate even if the buffer shifts
              (push (list (copy-marker heading-pos) real-start real-end) tasks)))
          (outline-next-heading)))

      ;; PHASE 2: Process the collected list
      (when tasks
        (org-history-outline--process-tasks (nreverse tasks) (unless (or page-beg page-end) t)))))

;; -=-= git blame
(defun org-history-outline--vc-git-blame-file (file)
  "Return a hash table mapping line numbers to last modification for FILE.

An optimized version of `org-history--vc-git-get-range-last-mod-date'.
Uses `default-directory'.

The returned hash table uses `eql' as its test, where keys are line
numbers (integers starting from 1) and values are plain strings representing
the last modification date formatted as \"YYYY-MM-DD\".

FILE should be relative to default-directory or full path.
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
          ;; -w Ignore whitespace when comparing the parent’s version and the child’s to find where the lines came from.
          ;; -M[<num>] Git detects movement and attributes the line to the original date , rather than new commit.
          ;; <num> is optional, but it is the lower bound on the
          ;; number of alphanumeric characters that Git must detect as
          ;; moving/copying within a file for it to associate those lines with the
          ;; parent commit. The default value is
          (when (zerop (vc-git-command t 0 nil "blame" "-M" "-w" "--date=short" "-c" file))
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

;; -=-= Process-tasks
(defvar-local org-history-outline--git-blame-cache nil
  "Cache for optimization: Hastable - Key is line-num, value is date-str.")
(defvar-local org-history-outline--git-last-commit nil
  "Used to check if cache required to be updated.")

(defun org-history-outline--process-tasks (tasks &optional set-oldest)
  "Process TASKS instantly by pre-caching Git blame data using native loops.
If optional argument SET-OLDEST, `org-history-outline-max-days' will be
 set to oldest date during applying if it not older than
 `org-history-outline-max-days' orginal value."
  (org-history-debug-print "org-history-outline--process-tasks N1 %s %s" org-history-outline--git-last-commit)
  (when-let ((commit-hash (org-history--vc-git-get-last-commit-hash buffer-file-name)))
    (unless (string-equal commit-hash org-history-outline--git-last-commit)
      (setq org-history-outline--git-blame-cache (org-history-outline--vc-git-blame-file buffer-file-name))
      (setq org-history-outline--git-last-commit commit-hash))
    (org-history-debug-print "org-history-outline--process-tasks N2")
    ;; PHASE 1: Process ranges instantly using native loops
    (when org-history-outline--git-blame-cache
      (let* (file-oldest
             max-days
             (tasks-with-dates
              (mapcar (lambda (task)
                        (let ((marker (nth 0 task))
                              (start  (nth 1 task))
                              (end    (nth 2 task))
                              (latest "1970-01-01"))
                          ;; Native loop over the line range to find the newest date
                          (let ((l start))
                            (while (<= l end)
                              (let ((l-date (gethash l org-history-outline--git-blame-cache)))
                                (when (and l-date (string> l-date latest))
                                  (setq latest l-date)))
                              (setq l (1+ l))))
                          ;; Now update file-oldest with the oldest date found
                          (when (and (not (string= latest "1970-01-01"))
                                     (or (not file-oldest)
                                         (string< latest file-oldest)))
                            (setq file-oldest latest))
                          ;; Return pair: (marker . date-str) or nil if unchanged from epoch
                          (cons marker (unless (string= latest "1970-01-01") latest))))
                      tasks)))
        (org-history-debug-print "org-history-outline--process-tasks N2 %s" set-oldest file-oldest)

        (when (and set-oldest file-oldest)
          (setq max-days (- (org-today) (org-time-string-to-absolute file-oldest))) ; in repo
          (setq org-history-outline-max-days max-days)
          (org-history-debug-print "org-history-outline--process-tasks N3 %s" max-days (org-today) (org-time-string-to-absolute file-oldest))
          ;; check boundaries
          (if (> max-days org-history-outline-max-days)
              (setq org-history-outline-max-days org-history-outline-max-days)
            ;; else
            (when (< max-days org-history-outline-min-days)
              (setq org-history-outline-max-days org-history-outline-min-days)))
          (message "org-history: max-days set to %s days." org-history-outline-max-days))

        ;; PHASE 2: Apply Overlays using native dolist
        (dolist (cell tasks-with-dates)
          (let ((marker (car cell))
                (date-str (cdr cell)))
            (when date-str
              ;; (with-current-buffer (marker-buffer marker)
              (save-excursion
                (goto-char (marker-position marker))
                (org-history-outline--outline-attach-date date-str)))
            (set-marker marker nil)))))))


;;; provide

(provide 'org-history-outline)

;;; org-history-outline.el ends here
