;;; test-stats-writes.el --- check how often stats are written   -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Michael Herstine <sp1ff@pobox.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; In #38 (<https://github.com/sp1ff/elfeed-score/issues/38>) some questions
;; were raised in terms of how often stats are written to file. This file
;; implements a simple test of the matter: they _should_ be written after
;; a sufficiently large number of rule matches, and on completion of an
;; update.

;;; Code:
(require 'cl-lib)

(defvar srcdir (getenv "srcdir"))
(cl-assert srcdir t "Please specify the env var srcdir.")

(defvar
 test-dir
 (concat
  (make-temp-name (concat (temporary-file-directory) ".elfeed-score-stats-writes-tests")) "/"))

(if (file-exists-p test-dir)
    (delete-directory test-dir t))
(make-directory test-dir)

(setq
 elfeed-feeds
 ;; This is a bit dicey as a testing strategy, but these two feeds typically
 ;; have few (like, less than a dozen) entries.
 '("https://sachachua.com/blog/category/emacs-news/feed/"
   ("http://rayhosler.wordpress.com/feed/" cycling))
 elfeed-db-directory test-dir
 elfeed-score-score-file (concat test-dir "elfeed.score")
 elfeed-score-rule-stats-file (concat test-dir "elfeed.stats")
 elfeed-search-print-entry-function #'elfeed-score-print-entry
 elfeed-score-log-level 'debug)

(require 'elfeed-score)

(defvar number-of-writes 0
  "Number of times `elfeed-score-rule-stats-write' has been invoked.")

(advice-add
 'elfeed-score-rule-stats-write
 :after
 (lambda (&rest _) (setq number-of-writes (1+ number-of-writes))))

;; Ensure these rules will match:
(with-temp-file
    elfeed-score-score-file
  (insert "((version 5)
(\"title\"
  (\".*\" 100 r))
)
"))

(elfeed-score-enable)
(elfeed)

(let ((elfeed-score-rule-stats-dirty-threshold 1024))
  (elfeed-search-fetch nil))

(defconst max-count 2048)
(let ((count 0))
  (while (and (> (elfeed-queue-count-total) 0) (< count max-count))
    (sit-for 2)
    (while (accept-process-output nil 2))
    (setq count (1+ count))
    (message "Beginning update...%s" (make-string count ?.)))
  (message
   "Beginning update...%s(%s[%d])"
   (make-string count ?.)
   (if (eq count max-count) "FAILED" "complete")
   count))

;; There is a small gap between `elfeed-curl-queue-active' dropping to zero &
;; the hook being invoked, meaning that we *could* be here without the stats
;; file being on disk (and I have actually oberved this). Cf.
;; `elfeed-curl--queue-wrap'.
(let ((count 0))
  (while (and (not (file-exists-p elfeed-score-rule-stats-file))
              (< count max-count))
    (sit-for 2)
    (while (accept-process-output nil 0))
    (setq count (1+ count))
    (message "Checking for stats on disk...%s" (make-string count ?.)))
  (message
   "Checking for stats on disk...%s(%s)"
   (make-string count ?.)
   (if (eq count max-count) "FAILED" "complete")))

;; This should all result in exactly one write.
(cl-assert (eq 1 number-of-writes))
