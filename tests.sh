#!/bin/bash
emacs -Q --batch --no-site-file -l org-history-debug.el -l org-history-outline.el -l org-history-dirl.el -l org-history.el -l org-history-test.el -f ert-run-tests-batch-and-exit || exit 1
emacs -Q --batch --no-site-file -l org-history-debug.el -l org-history-outline.el -l org-history-outline-test.el -f ert-run-tests-batch-and-exit || exit 1
emacs -Q --batch --no-site-file -l org-history-debug.el -l org-history-dirl.el -l org-history-dirl-test.el -f ert-run-tests-batch-and-exit || exit 1
# Single:
# emacs -Q --batch --no-site-file \
#   -l org-history-debug.el \
#   -l org-history-outline.el \
#   -l org-history.el \
#   -l test-org-history.el \
#   --eval "(ert-run-tests-batch-and-exit 'test-org-history-mode-activation)" || exit 1
