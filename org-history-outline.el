;;; org-history-outline.el --- Attach dates at the end of Org outlines -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'color)

(defun org-history-outline-attach-date (date-str)
  "Attach overlay with date at the end header with color gradient.
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
         (max-days 360)
         (ratio (/ (min days-old max-days) (float max-days)))
         (hue (* ratio 0.66)) ; 0.0 = Red, 0.66 = Blue
         (rgb (color-hsl-to-rgb hue 0.8 0.5))
         (color-hex (apply #'color-rgb-to-hex rgb)))

    ;; 3. CLEANUP: Wipe old overlays utilizing the "line-end + 1" boundary trick
    (remove-overlays (line-beginning-position) (1+ (line-end-position)) 'identity 'my-org-date)

    ;; 4. CREATION: Render the overlay text onto the line boundary
    (let ((ov (make-overlay (line-end-position) (line-end-position))))
      (overlay-put ov 'identity 'my-org-date)
      (overlay-put ov 'priority 100)
      (overlay-put ov 'after-string
                   (propertize (format "  [%s]" date-str)
                               'face `(:foreground ,color-hex :weight bold)
                               'help-echo (format "Age: %d days old" days-old)
                               'read-only t
                               'intangible t
                               'cursor-intangible t)))))

(defun my-clear-all-org-date-overlays ()
  "Instantly remove all custom date overlays from the entire buffer."
  (interactive)
  (remove-overlays (point-min) (point-max) 'identity 'my-org-date)
  (font-lock-flush)
  (message "Successfully cleared all header date overlays."))


(provide 'org-history-outline)

;;; org-history.el ends here
