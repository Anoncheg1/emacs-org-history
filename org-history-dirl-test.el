;;; org-history-dirl-test.el --- Tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>
;; URL: https://codeberg.org/Anoncheg/emacs-org-history
;; Version: 0.2
;; Package-Requires: ((emacs "29.1"))

(require 'ert)
(require 'cl-lib)
(require 'org-history-dirl)

(setopt org-history-debug-ert-enabled nil)
;;; Code:

(defconst org-history--mock-per-file1
  '(("folder1/file"     ((org-mode . ((mode . org-history)))))))

(defconst org-history--mock-per-file2
  '(("folder1/file"     (org-mode . ((mode . org-history))))))

(defconst org-history--mock-per-file3
  '(("folder1/file"     (org-mode . (mode . org-history)))))

(defconst org-history--mock-per-mode
  '((org-mode . ((mode . org-history)))))

(defconst org-history--mock-nil
  '((nil . ((mode . org-history)))))

;; Negative Edge Case 1: Wrong major mode specified
(defconst org-history--mock-wrong-major-mode
  '((text-mode . ((mode . org-history)))))

;; Negative Edge Case 2: Wrong minor mode specified (same structure, different mode)
(defconst org-history--mock-wrong-minor-mode
  '((org-mode . ((mode . electric-indent)))))

;; Negative Edge Case 3: Proper-list instead of dotted-pair syntax (Should succeed)
(defconst org-history--mock-proper-list-syntax
  '((org-mode . ((mode org-history)))))

;; Negative Edge Case 4: Malformed structure (empty settings or incorrect type structures)
(defconst org-history--mock-malformed-nil
  '((nil . nil)))

(defconst org-history--mock-malformed-mode
  '((org-mode . (mode)))) ; Symbol instead of a cons or list of variables


;; =============================================================================
;; ERT Tests
;; =============================================================================
(ert-deftest  org-history-dirl-test--dir-locals-all-entries ()
    (should-not (org-history-dirl--filter-list-by-car 'org-mode org-history--mock-per-file1))
    (should (equal (org-history-dirl--filter-list-by-car 'org-mode org-history--mock-per-mode)
                   '((mode . org-history)))))

(ert-deftest org-history-dirl-test--contains-mode-p ()
  (should (org-history-dirl--contains-mode-p '(org-mode . (mode . org-history)) 'org-mode 'org-history))
  (should (org-history-dirl--contains-mode-p '(org-mode . ((mode . org-history))) 'org-mode 'org-history))
  (should (org-history-dirl--contains-mode-p '((org-mode . (mode . org-history))) 'org-mode 'org-history))
  (should (org-history-dirl--contains-mode-p '((org-mode . ((mode . org-history)))) 'org-mode 'org-history)))

(ert-deftest org-history-dirl-test--dir-locals-per-file-test ()
  ;; (assoc  'org-mode '((org-mode (mode . org-history))))

  ;; Positive cases
  (should (org-history-dirl--dir-locals-p "folder1/file" org-history--mock-per-file1))
  (should (org-history-dirl--dir-locals-p "folder1/file" org-history--mock-per-file2))
  (should (org-history-dirl--dir-locals-p "folder1/file" org-history--mock-per-file3))
  ;; Negative cases
  (should-not (org-history-dirl--dir-locals-p "otherfile" org-history--mock-per-file1))
  (should-not (org-history-dirl--dir-locals-p "otherfile" org-history--mock-per-file2))
  (should-not (org-history-dirl--dir-locals-p "otherfile" org-history--mock-per-file3))
  (should-not (org-history-dirl--dir-locals-p "folder1/file" org-history--mock-wrong-minor-mode)))

(ert-deftest org-history-dirl-test--locals-per-mode-test ()
  ;; Positive cases
  (should (org-history-dirl--dir-locals-p "anyfile" org-history--mock-per-mode))
  (should (org-history-dirl--dir-locals-p nil       org-history--mock-per-mode))
  ;; Negative cases (Wrong major mode configured in .dir-locals.el)
  (should-not (org-history-dirl--dir-locals-p "anyfile" org-history--mock-wrong-major-mode)))

(ert-deftest org-history-dirl-test--locals-nil-test ()
  ;; Positive cases
  (should (org-history-dirl--dir-locals-p "anyfile" org-history--mock-nil))
  (should (org-history-dirl--dir-locals-p nil       org-history--mock-nil))
  ;; Negative cases (Wrong minor mode under nil block)
  (should-not (org-history-dirl--dir-locals-p "anyfile" '((nil . ((mode . some-other-mode)))))))

(ert-deftest org-history-dirl-test--locals-all-cases-per-file ()
  ;; Positive cases
  (should (org-history-dirl--dir-locals-p "folder1/file" org-history--mock-per-file1))
  ;; Negative cases
  (should-not (org-history-dirl--dir-locals-p "otherfile"    org-history--mock-per-file1))
  (should-not (org-history-dirl--dir-locals-p "folder1/file" org-history--mock-wrong-major-mode)))

(ert-deftest org-history-dirl-test--locals-all-cases-per-mode ()
  ;; Positive cases
  (should (org-history-dirl--dir-locals-p "anyfile" org-history--mock-per-mode))
  (should (org-history-dirl--dir-locals-p nil       org-history--mock-per-mode))
  ;; Negative cases
  (should-not (org-history-dirl--dir-locals-p "anyfile" org-history--mock-wrong-minor-mode)))

(ert-deftest org-history-dirl-test--locals-all-cases-nil ()
  ;; Positive cases
  (should (org-history-dirl--dir-locals-p "anyfile" org-history--mock-nil))
  (should (org-history-dirl--dir-locals-p nil       org-history--mock-nil)))

;; New Dedicated Edge Cases Suite
(ert-deftest org-history-dirl-test--edge-cases ()
  ;; 1. Standard syntax variance: proper list `(mode org-history)` instead of dotted pair
  (should-not (org-history-dirl--dir-locals-p "anyfile" org-history--mock-proper-list-syntax))

  ;; 2. Empty configuration
  (should-not (org-history-dirl--dir-locals-p "anyfile" nil))

  ;; 3. Malformed configurations (should evaluate to nil/false instead of throwing errors)
  (should-not (org-history-dirl--dir-locals-p "anyfile" org-history--mock-malformed-nil))
  (should-not (org-history-dirl--dir-locals-p "anyfile" org-history--mock-malformed-mode)))

;; -=-= another
(ert-deftest org-history-dirl-test--dird-append-merges-and-adds-entry ()
  "Test that org-history-dirl-append merges .dir-locals.el, preserves existing config, and adds org-history activation for visited file."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "ert-test-" t)))
         (target-file (expand-file-name ".dir-locals.el" temp-dir))
         (dummy-file (expand-file-name "dummy.org" temp-dir))
         (initial-config '((python-mode . ((python-indent-offset . 4)))
                           (org-mode . ((org-todo-keywords . ("TODO" "DONE")))))))
    (unwind-protect
        (progn
          ;; Write initial .dir-locals.el
          (with-temp-file target-file
            (pp initial-config (current-buffer)))
          ;; Create dummy.org file
          (with-temp-file dummy-file
            (insert "some org content"))
          ;; Open the file and call main function
          (find-file dummy-file)
          (let ((default-directory temp-dir))
            (org-history-dirl-append))
          ;; Now inspect .dir-locals.el
          (with-temp-buffer
            (insert-file-contents target-file)
            (let ((result (read (current-buffer))))
              ;; 1. Original python-mode config preserved
              (should (equal (cdr (assoc 'python-mode result))
                             '((python-indent-offset . 4))))
              ;; 2. Original org-mode config preserved
              (should (member '(org-todo-keywords . ("TODO" "DONE"))
                              (cdr (assoc 'org-mode result))))
              ;; 3. New dummy.org entry exists with org-history activation
              (let* ((rel-dummy-file (file-relative-name dummy-file temp-dir))
                     (dummy-entry (assoc rel-dummy-file result)))
                (should dummy-entry)
                (let ((org-mode-part (assoc 'org-mode (cdr dummy-entry))))
                  (should org-mode-part)
                  (should (member '(mode . org-history)
                                  (cdr org-mode-part))))))))
      ;; Cleanup buffers and tempdir
      (when (get-file-buffer dummy-file)
        (kill-buffer (get-file-buffer dummy-file)))
      (when (get-file-buffer target-file)
        (kill-buffer (get-file-buffer target-file)))
      (delete-directory temp-dir t))))

;; -=-=

(provide 'org-history-dirl-test)

;;; org-history-dirl-test.el ends here
