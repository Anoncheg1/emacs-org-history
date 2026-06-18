;;; org-history-outline-test.el --- Tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 github.com/Anoncheg1,codeberg.org/Anoncheg
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; Author: <github.com/Anoncheg1,codeberg.org/Anoncheg>
;; URL: https://codeberg.org/Anoncheg/emacs-org-history
;; Version: 0.2
;; Package-Requires: ((emacs "29.1"))

(require 'ert)
(require 'cl-lib)

;; Dummy global variables required by the code framework if not already defined
;;; Code:

;; Ensure structural variables are set for the integration execution environment

(ert-deftest test-org-history-outline--add-dates-sync-cache-miss ()
  "Test `org-history-outline--add-dates' under a cache miss for a small file (Synchronous path)."
  (with-temp-buffer
    (org-mode)
    (insert "* Task 1\n* Task 2\n")
    (setq buffer-file-name "/mock/path/to/test-file.org")

    (let* ((m1 (make-marker))
           (m2 (make-marker))
           (tasks (list (list m1 1 1) (list m2 2 2)))
           (mock-commit "abcdef1234567890"))

      (set-marker m1 1)
      (set-marker m2 (progn (goto-char (point-min)) (forward-line 1) (point)))

      (cl-letf* (;; FIX: Provide a well-formed 8-element list so (file-attribute-size) returns 500
                 ((symbol-function 'file-attributes)
                  (lambda (_file) (list nil nil nil nil nil nil nil 500)))
                 ((symbol-function 'org-history-outline--git-blame-file-main)
                  (lambda (_file &optional _async)
                    (let ((table (make-hash-table :test 'eql)))
                      (puthash 1 "2026-01-01" table)
                      (puthash 2 "2026-01-02" table)
                      table))))

        (setq org-history-outline--git-last-commit nil)
        (setq org-history-outline--git-blame-cache nil)

        (org-history-outline--add-dates tasks mock-commit)

        ;; Verifications
        (should (string-equal org-history-outline--git-last-commit mock-commit))
        (should (hash-table-p org-history-outline--git-blame-cache))

        (goto-char (point-min))
        (let ((ovs (overlays-at (1- (line-end-position)))))
          (should ovs)
          (should (eq (overlay-get (car ovs) 'identity) 'my-org-date)))))))

(ert-deftest test-org-history-outline--add-dates-async-large-file ()
  "Test `org-history-outline--add-dates' handling when file size exceeds 200KB."
  (with-temp-buffer
    (org-mode)
    (insert "* Heavy Task Node 1\n* Heavy Task Node 2\n")
    (setq buffer-file-name "/mock/path/heavy-file.org")

    (let* ((m1 (make-marker))
           (m2 (make-marker))
           (tasks (list (list m1 1 1) (list m2 2 2)))
           (mock-commit "async-commit-hash")
           (async-callback-called nil))

      (set-marker m1 1)
      (set-marker m2 (progn (goto-char (point-min)) (forward-line 1) (point)))

      (setq org-history-outline--git-last-commit nil)
      (setq org-history-outline--git-blame-cache nil)

      (cl-letf* (;; FIX: Provide a well-formed 8-element list so (file-attribute-size) returns 300KB
                 ((symbol-function 'file-attributes)
                  (lambda (_file) (list nil nil nil nil nil nil nil (* 300 1024))))
                 ((symbol-function 'org-history-outline--git-blame-file-main)
                  (lambda (_file async-callback)
                    (should async-callback)
                    (let ((mock-table (make-hash-table :test 'eql)))
                      (puthash 1 "2026-06-15" mock-table)
                      (puthash 2 "2026-06-18" mock-table)
                      (funcall async-callback mock-table)
                      (setq async-callback-called t)))))

        (org-history-outline--add-dates tasks mock-commit)

        ;; Verifications
        (should async-callback-called)
        (should (string-equal org-history-outline--git-last-commit mock-commit))

        (goto-char (point-min))
        (let ((ovs-line1 (overlays-at (1- (line-end-position)))))
          (should ovs-line1)
          (should (eq (overlay-get (car ovs-line1) 'identity) 'my-org-date)))))))


(ert-deftest test-org-history-outline--add-dates-hit-cache ()
  "Test `org-history-outline--add-dates' when cache is hot and match-ready."
  (with-temp-buffer
    (org-mode)
    (insert "* Existing Task\n")
    (setq buffer-file-name "/mock/path/to/test-file.org")

    (let* ((m1 (make-marker))
           (tasks (list (list m1 1 1)))
           (mock-commit "same-commit-hash")
           (pre-filled-cache (make-hash-table :test 'eql)))

      (set-marker m1 1)
      (puthash 1 "2026-05-10" pre-filled-cache)

      (setq org-history-outline--git-last-commit mock-commit)
      (setq org-history-outline--git-blame-cache pre-filled-cache)

      (cl-letf* (((symbol-function 'file-attributes)
                  (lambda (_file) (list nil nil nil nil nil nil nil 500)))
                 ;; Fail fast if the function mistakenly drops into file parsing routines
                 ((symbol-function 'org-history-outline--git-blame-file-main)
                  (lambda (&rest _args) (error "Should not be called during a hot cache hit!"))))

        ;; FIX: Don't check return value. Just call it for its overlay side-effects.
        (org-history-outline--add-dates tasks mock-commit)

        ;; VERIFICATION: Confirm that the overlay was attached cleanly from cache processing
        (goto-char (point-min))
        (let ((ovs (overlays-at (1- (line-end-position)))))
          (should ovs)
          (should (eq (overlay-get (car ovs) 'identity) 'my-org-date)))))))


(provide 'org-history-outline-test)

;;; org-history-outline-test.el ends here
