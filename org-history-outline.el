;;; org-history-outline.el --- Attach dates at the end of Org outlines -*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>

;;; Commentary:

;; To get date use `org-history--vc-git-get-range-last-mod-date'.

;;; Code:

(require 'color)

;; (defun org-history-outline--outline-attach-date (date-str)
;;   "Attach overlay with date at the end header with color gradient.
;; Cursors should be at header position.
;; Smooth vc-annotate color gradient is used by how old date is.
;; Overlay is not modifiable and dont modify buffer content.
;; Automatically deletes older date overlays on the same headline when updated."
;;   (interactive "sEnter date (YYYY-MM-DD): ")
;;   (let* ((time-attr (condition-case nil
;;                         (date-to-time date-str)
;;                       (error (user-error "Invalid date format! Use YYYY-MM-DD"))))
;;          ;; 1. Max out at 0 to avoid future negative date math bugs safely in one line
;;          (days-old (max 0 (floor (- (float-time) (float-time time-attr)) 86400)))

;;          ;; 2. Generate smooth vc-annotate aging color wheel
;;          (max-days 360)
;;          (ratio (/ (min days-old max-days) (float max-days)))
;;          (hue (* ratio 0.66)) ; 0.0 = Red, 0.66 = Blue
;;          (rgb (color-hsl-to-rgb hue 0.8 0.5))
;;          (color-hex (apply #'color-rgb-to-hex rgb))
;;          (lend (1- (line-end-position)))) ; without -1 date will be visible only on opened.

;;     ;; 3. CLEANUP: Wipe old overlays utilizing the "line-end + 1" boundary trick
;;     (remove-overlays lend (1+ lend) 'identity 'my-org-date)

;;     ;; 4. CREATION: Render the overlay text onto the line boundary
;;     (let ((ov (make-overlay lend lend)))
;;       (overlay-put ov 'identity 'my-org-date)
;;       (overlay-put ov 'priority 100)
;;       (overlay-put ov 'after-string
;;                    (propertize (format "  [%s]" date-str)
;;                                'face `(:foreground ,color-hex :weight bold)
;;                                'help-echo (format "Age: %d days old" days-old)
;;                                'read-only t
;;                                'intangible t
;;                                'cursor-intangible t)))))

;; (defun org-history-outline--outline-attach-date (date-str)
;;   "Attach overlay with date at the end header with color gradient.
;; Cursors should be at header position.
;; Smooth vc-annotate color gradient is used by how old date is.
;; Overlay is not modifiable and dont modify buffer content.
;; Automatically deletes older date overlays on the same headline when updated."
;;   (interactive "sEnter date (YYYY-MM-DD): ")
;;   (let* ((time-attr (condition-case nil
;;                         (date-to-time date-str)
;;                       (error (user-error "Invalid date format! Use YYYY-MM-DD"))))
;;          ;; 1. Max out at 0 to avoid future negative date math bugs safely in one line
;;          (days-old (max 0 (floor (- (float-time) (float-time time-attr)) 86400)))
;;          ;; 2. Generate smooth vc-annotate aging color wheel
;;          (max-days 360)
;;          (ratio (/ (min days-old max-days) (float max-days)))
;;          (hue (* ratio 0.66)) ; 0.0 = Red, 0.66 = Blue
;;          (rgb (color-hsl-to-rgb hue 0.8 0.5))
;;          (color-hex (apply #'color-rgb-to-hex rgb))
;;          ;; (lend (1- (line-end-position))) ; without -1 date will be visible only on opened.
;;          (lend (line-end-position))
;;          ;; --- NEW: Define your target alignment column ---
;;          (target-column 60))

;;     ;; 3. CLEANUP: Wipe old overlays utilizing the "line-end + 1" boundary trick
;;     (remove-overlays lend (1+ lend) 'identity 'my-org-date)

;;     ;; 4. CREATION: Render the overlay text onto the line boundary
;;     (let ((ov (make-overlay lend lend)))
;;       (overlay-put ov 'identity 'my-org-date)
;;       (overlay-put ov 'priority 100)
;;       (overlay-put ov 'after-string
;;                    (concat
;;                     ;; Dynamic spacer that pushes the text to target-column
;;                     (propertize " " 'display `(space :align-to ,target-column))
;;                     ;; Your formatted date
;;                     (propertize (format "[%s]" date-str)
;;                                 'face `(:foreground ,color-hex :weight bold)
;;                                 'help-echo (format "Age: %d days old" days-old)
;;                                 'read-only t
;;                                 'intangible t
;;                                 'cursor-intangible t))))))

;; (defun org-history-outline--outline-attach-date (date-str)
;;   "Attach overlay with date at the end header with color gradient.
;; Cursors should be at header position.
;; Smooth vc-annotate color gradient is used by how old date is.
;; Overlay is not modifiable and dont modify buffer content.
;; Automatically deletes older date overlays on the same headline when updated."
;;   (interactive "sEnter date (YYYY-MM-DD): ")
;;   (let* ((time-attr (condition-case nil
;;                         (date-to-time date-str)
;;                       (error (user-error "Invalid date format! Use YYYY-MM-DD"))))
;;          ;; 1. Max out at 0 to avoid future negative date math bugs safely in one line
;;          (days-old (max 0 (floor (- (float-time) (float-time time-attr)) 86400)))
;;          ;; 2. Generate smooth vc-annotate aging color wheel
;;          (max-days 360)
;;          (ratio (/ (min days-old max-days) (float max-days)))
;;          (hue (* ratio 0.66)) ; 0.0 = Red, 0.66 = Blue
;;          (rgb (color-hsl-to-rgb hue 0.8 0.5))
;;          (color-hex (apply #'color-rgb-to-hex rgb))

;;          ;; --- THE SOLUTION ---
;;          ;; Look at the last actual string character of the header (just before \n)
;;          (lend (line-end-position))
;;          (lstart (1- lend))
;;          (target-column 60))

;;     ;; 3. CLEANUP: Clear overlays sitting exactly on that last character slot
;;     (remove-overlays lstart lend 'identity 'my-org-date)

;;     ;; 4. CREATION: Render the overlay text natively inside the engine layout block
;;     (let* ((ov (make-overlay lstart lend))
;;            ;; Extract the exact single final character of the heading text
;;            (last-char (buffer-substring-no-properties lstart lend)))
;;       (overlay-put ov 'identity 'my-org-date)
;;       (overlay-put ov 'priority 100)

;;       ;; We use 'display property to tell Emacs:
;;       ;; "Draw the last character normally, then space over to column 60, then append the date"
;;       (overlay-put ov 'display
;;                    (concat
;;                     last-char
;;                     (propertize " " 'display `(space :align-to ,target-column))
;;                     (propertize (format "[%s]" date-str)
;;                                 'face `(:foreground ,color-hex :weight bold)
;;                                 'help-echo (format "Age: %d days old" days-old)
;;                                 'read-only t
;;                                 'intangible t
;;                                 'cursor-intangible t))))))


;; (defun org-history-outline--outline-attach-date (date-str)
;;   "Attach overlay with date at the end header with color gradient.
;; Cursors should be at header position.
;; Smooth vc-annotate color gradient is used by how old date is.
;; Overlay is not modifiable and dont modify buffer content.
;; Automatically deletes older date overlays on the same headline when updated."
;;   (interactive "sEnter date (YYYY-MM-DD): ")
;;   (let* ((time-attr (condition-case nil
;;                         (date-to-time date-str)
;;                       (error (user-error "Invalid date format! Use YYYY-MM-DD"))))
;;          ;; 1. Max out at 0 to avoid future negative date math bugs safely in one line
;;          (days-old (max 0 (floor (- (float-time) (float-time time-attr)) 86400)))
;;          ;; 2. Generate smooth vc-annotate aging color wheel
;;          (max-days 360)
;;          (ratio (/ (min days-old max-days) (float max-days)))
;;          (hue (* ratio 0.66)) ; 0.0 = Red, 0.66 = Blue
;;          (rgb (color-hsl-to-rgb hue 0.8 0.5))
;;          (color-hex (apply #'color-rgb-to-hex rgb))

;;          ;; --- THE RE-FIX ---
;;          (lend (line-end-position))
;;          (lstart (1- lend))
;;          (target-column 60))

;;     ;; 3. CLEANUP: Clear overlays sitting exactly on that last character slot
;;     (remove-overlays lstart lend 'identity 'my-org-date)

;;     ;; 4. CREATION: Render the layout safely
;;     (let* ((ov (make-overlay lstart lend))
;;            (last-char (buffer-substring-no-properties lstart lend))
;;            ;; Build the layout components cleanly
;;            (spacer " ")
;;            (date-text (propertize (format " [%s]" date-str)
;;                                   'face `(:foreground ,color-hex :weight bold)
;;                                   'help-echo (format "Age: %d days old" days-old)
;;                                   'read-only t
;;                                   'intangible t
;;                                   'cursor-intangible t)))

;;       ;; Apply the alignment property directly to our spacer string wrapper
;;       (put-text-property 0 1 'display `(space :align-to ,target-column) spacer)

;;       (overlay-put ov 'identity 'my-org-date)
;;       (overlay-put ov 'priority 100)

;;       ;; Flatten the display string sequence cleanly so the display engine processes it
;;       (overlay-put ov 'display (concat last-char spacer date-text)))))


(defcustom org-history-outline-max-days (* 360 2)
  "Maximum number of days to keep in the outline history.
This value must be an integer representing the day retention threshold."
  :group 'org-history
  :type 'integer
  :local t
  :safe #'integerp)

(defcustom org-history-outline-min-days 90
  "Minimum number of days to keep in the outline history.
This value must be an integer representing the day retention threshold."
  :group 'org-history
  :type 'integer
  :local t
  :safe #'integerp)

(defcustom org-history-outline-date-column 60
  "Column to put date at."
  :group 'org-history
  :type 'integer
  :safe #'integerp)

(defun org-history-outline--outline-attach-date (date-str)
  "Attach overlay with date at the end header with color gradient.
Cursors should be at header position.
Smooth vc-annotate color gradient is used by how old date is.
Overlay is not modifiable and dont modify buffer content.
Automatically deletes older date overlays on the same headline when updated."
  (interactive "sEnter date (YYYY-MM-DD): ")
  (let* ((time-attr (condition-case nil
                        (date-to-time date-str)
                      (error (user-error "Invalid date format! Use YYYY-MM-DD"))))
         ;; 1. Max out at 0 to avoid future negative date math bugs safely in one line
         (days-old (max 0 (floor (- (float-time) (float-time time-attr)) 86400)))
         ;; 2. Generate smooth vc-annotate aging color wheel
         ;; (max-days 360)
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

;; (defun org-history-outline--add-dates ()
;;   "Print buffer positions for the content of all visible Org headings."
;;   (interactive)
;;   (org-map-entries

;;    (lambda ()
;;      ;; Explicitly skip if the current heading itself is folded/invisible
;;      ;; Optimizated version of `org-fold-folded-p' for outlines only
;;      ;; checked as (progn (forward-line 1) (org-fold-folded-p (point) 'headline))
;;      ;; (org-fold-folded-p (point) 'headline)
;;      (unless (org-fold-core-get-folding-spec 'headline (point))
;;        (let* ((start (save-excursion (forward-line 1) (line-number-at-pos)))
;;               (end (save-excursion (org-end-of-subtree t t) (line-number-at-pos)))
;;               (start (min start end))
;;               (end (max start end))
;;               (date-str (org-history--vc-git-get-range-last-mod-date buffer-file-name start end)))
;;          ;; (point) - at begin of heading
;;          (org-history-outline--outline-attach-date date-str)
;;          ;; (message "Heading: \"%s\" | (%d . %d) | %s"
;;          ;;          (org-get-heading t t t t) start (max start end) date-str)
;;          ))) ; end of lambda

;;    t 'file))

;; --------------------------------------------------------
(defun org-history-outline--add-dates (&optional page-beg page-end)
  "Collect line ranges for visible Org headings and apply dates separately.
Optional arguments PAGE-BEG PAGE-END are position in current buffer."
  (interactive)
  (when (org-history--vc-git-get-last-commit-date) ; or gethash(4 nil) error in `org-history-outline--process-tasks'
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
      ;; (message "Heading markers collected.")

      ;; PHASE 2: Process the collected list
      (if tasks
          (org-history-outline--process-tasks (nreverse tasks) (unless (or page-beg page-end) t))
        (message "No visible headings found.")))))

;; (defun org-history-outline--process-tasks (tasks)
;;   "Loop through TASKS to fetch Git dates and apply overlays."
;;   (let* ((total (length tasks))
;;          (counter 0)
;;          (reporter (make-progress-reporter "Fetching Git dates..." 0 total)))
;;     (dolist (task tasks)
;;       (let* ((marker (nth 0 task))
;;              (start-line (nth 1 task))
;;              (end-line (nth 2 task)))

;;         ;; Move to the heading safely using the marker
;;         (with-current-buffer (marker-buffer marker)
;;           (save-excursion
;;             (goto-char (marker-position marker))

;;             ;; Fetch the date and attach
;;             (let ((date-str (org-history--vc-git-get-range-last-mod-date
;;                              buffer-file-name start-line end-line)))
;;               (org-history-outline--outline-attach-date date-str)
;;               )))

;;         ;; Clean up marker memory
;;         (set-marker marker nil)

;;         ;; Update progress bar in the minibuffer
;;         (setq counter (1+ counter))
;;         (progress-reporter-update reporter counter)))
;;     (progress-reporter-done reporter)
;;     (message "Successfully processed %d headings." total)))

;; (defun org-history-outline--process-tasks (tasks)
;;   "Process TASKS by fetching Git dates first, then applying overlays in separate loops."
;;   (let (tasks-with-dates)

;;     ;; PHASE 1: Fetch Git dates (Slow I/O Loop)
;;     (setq tasks-with-dates
;;           (mapcar (lambda (task)
;;                     (let ((marker (nth 0 task))
;;                           (start (nth 1 task))
;;                           (end (nth 2 task)))
;;                       (cons marker (org-history--vc-git-get-range-last-mod-date
;;                                     buffer-file-name start end))))
;;                   tasks))
;;     (message "Successfully fetched Git dates.")

;;     ;; PHASE 2: Apply Overlays (Fast UI Loop using native dolist)
;;     (dolist (cell tasks-with-dates)
;;       (let ((marker (car cell))
;;             (date-str (cdr cell)))
;;         (with-current-buffer (marker-buffer marker)
;;           (save-excursion
;;             (goto-char (marker-position marker))
;;             (org-history-outline--outline-attach-date date-str)))
;;         (set-marker marker nil))) ; Free memory safely

;;     (message "Successfully processed %d headings." (length tasks))))
;; -------------------------------

(defvar-local org-history-outline--git-blame-cache nil
  "Hastable with: Key is line-num, value is date-str.")
(defvar-local org-history-outline--git-blame-tick nil)

(defun org-history-outline--process-tasks (tasks &optional set-oldest)
  "Process TASKS instantly by pre-caching Git blame data using native loops.
If optional argument SET-OLDEST, `org-history-outline-max-days' will be
 set to oldest date during applying if it not older than
 `org-history-outline-max-days' orginal value."
  (unless (eq org-history-outline--git-blame-tick (buffer-modified-tick))
    (setq org-history-outline--git-blame-cache (org-history--vc-git-blame-file buffer-file-name))
    (setq org-history-outline--git-blame-tick (buffer-modified-tick)))
  ;; PHASE 1: Process ranges instantly using native loops
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
                      (when (and (not (string= latest "1970-01-01"))
                                 (string< latest file-oldest))
                        (setq file-oldest latest))
                      ;; Return pair: (marker . date-str) or nil if unchanged from epoch
                      (cons marker (unless (string= latest "1970-01-01") latest))))
                  tasks)))

    (when (and set-oldest file-oldest)
      (setq max-days (- (org-today) (org-time-string-to-absolute file-oldest)))
      (if (and (< max-days org-history-outline-max-days) ; we dont exce
               (>= max-days org-history-outline-min-days))
          (setq org-history-outline-max-days (- (org-today) (org-time-string-to-absolute file-oldest))))
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
        (set-marker marker nil))))
  ;; (message "Successfully processed %d headings." (length tasks))
  )

;; ------------------------------------- timer ----------
(defvar org-history-outline--active-timer nil
  "Global reference to the running background outline timer.")

(defun org-history-outline--add-dates-stop-timer ()
  "Stop the active org-history outline timer and clean up the reporter."
  (interactive)
  (when org-history-outline--active-timer
    (cancel-timer org-history-outline--active-timer)
    (setq org-history-outline--active-timer nil)
    (message "Org history timer stopped.")))

(defun org-history-outline--add-dates-run-in-timer ()
  "Run `org-history-outline--add-dates' every second with a simple reporter."
  (interactive)

  ;; 1. Ensure no duplicate timers are running
  (when org-history-outline--active-timer
    (org-history-outline--add-dates-stop-timer))

  (let* ((current-buf (current-buffer))
         ;; 2. Initialize a simple non-deterministic progress reporter
         (reporter (make-progress-reporter "Processing Org history visibility...")))

    ;; 3. Start the repeating timer
    (setq org-history-outline--active-timer
          (run-with-timer
           1.0 1.0
           (lambda ()
             ;; Guard clause: Stop if the buffer was killed/closed
             (if (not (buffer-live-p current-buf))
                 (progn
                   (progress-reporter-done reporter)
                   (org-history-outline--add-dates-stop-timer))

               ;; Update the visual reporter spinner
               (progress-reporter-update reporter)

               ;; Execute your process safely inside the target buffer
               (with-current-buffer current-buf
                 (save-excursion
                   (condition-case err
                       (progn
                         (org-history-outline--add-dates)
                         (progress-reporter-done reporter)
                         (org-history-outline--add-dates-stop-timer))
                     (error
                      (message "Timer processing error: %s"
                               (error-message-string err))))))))))))
;; -------------------------------

(provide 'org-history-outline)

;;; org-history.el ends here
