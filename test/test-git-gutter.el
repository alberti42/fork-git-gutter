;;; test-git-gutter.el --- Test for git-gutter.el

;; Copyright (C) 2016-2020 Syohei YOSHIDA and Neil Okamoto

;; Author: Syohei YOSHIDA <syohex@gmail.com>
;; Maintainer: Neil Okamoto <neil.okamoto+melpa@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'ert)
(require 'vc)
(require 'git-gutter)

;; suppress log message
(setq git-gutter:verbosity 0)

(ert-deftest git-gutter:sign-width ()
  "helper function `git-gutter:sign-width'"
  (let ((got1 (git-gutter:sign-width "a"))
        (got2 (git-gutter:sign-width "0123456789")))
    (should (= got1 1))
    (should (= got2 10))))

(ert-deftest git-gutter:propertized-sign ()
  "helper function `git-gutter:propertized-sign'"
  (should (string= (git-gutter:propertized-sign 'added) "+")))

(ert-deftest git-gutter:changes-to-number ()
  "helper function `git-gutter:changes-to-number'"
  (should (= (git-gutter:changes-to-number "") 1))
  (should (= (git-gutter:changes-to-number "123") 123)))

(defun with-temporary-directory (test-fn)
  "Create a temp directory and execute TEST-FN within."
  (let (tmpdir)
    (unwind-protect
        (progn
          (setq tmpdir (make-temp-file "git-gutter-test-" t))
          (let* ((default-directory tmpdir))
            (funcall test-fn)))
      (delete-directory tmpdir t))))

(ert-deftest git-gutter:in-git-repository-p ()
  "True only if default-directory is a git repo."

  (with-temporary-directory
   (lambda ()
     ;; not in a git repository
     (should-not (git-gutter:in-git-repository-p))

     ;; now create the repo and check again
     (vc-create-repo 'Git)
     (should (git-gutter:in-git-repository-p))
     
     ;; ...but not inside the .git subdirectory itself #36
     (with-current-buffer (find-file-noselect ".git/config")
       (should-not (git-gutter:in-git-repository-p))))))

(ert-deftest git-gutter ()
  "Should return nil if buffer does not related with file or file is not existed"
  (with-current-buffer (get-buffer-create "*not-related-file*")
    (should-not (git-gutter)))
  (let ((buf (find-file-noselect "not-found")))
    (with-current-buffer buf
      (should-not (git-gutter)))))

(ert-deftest git-gutter:collect-deleted-line ()
  "Should return lines which start with '-'"
  (let* ((input (mapconcat 'identity
                           (list "-apple" "-melon" "+orange")
                           "\n"))
         (got (git-gutter:collect-deleted-line input)))
    (should (equal got '("apple" "melon")))))

(ert-deftest git-gutter:insert-deleted-lines ()
  "Should insert deleted line"
  (let ((input (mapconcat 'identity
                          (list "-apple" "-melon" "+orange")
                          "\n")))
    (with-temp-buffer
      (git-gutter:insert-deleted-lines input)
      (should (string= (buffer-string)
                       "apple\nmelon\n")))))

(ert-deftest git-gutter:diff-content ()
  "Should return diff hunk"
  (let* ((input "@@-1,1+1,1@@
foo
bar
@@ -2,2 +2,2 @@")
         (got (with-temp-buffer
                (insert input)
                (goto-char (point-min))
                (goto-char (line-end-position))
                (git-gutter:diff-content))))
    (should (string= got "@@-1,1+1,1@@\nfoo\nbar"))))

(ert-deftest git-gutter:set-window-margin ()
  "Should change window margin"
  (git-gutter:set-window-margin 4)
  (let ((got (car (window-margins))))
    (should (= got 4))))

(ert-deftest git-gutter-mode-success ()
  "Case git-gutter-mode enabled"
  (with-temporary-directory
   (lambda ()
     (vc-create-repo 'Git)
     (with-current-buffer (find-file-noselect "test.el")
       (git-gutter-mode 1)
       (should git-gutter-mode)))))

(ert-deftest git-gutter-mode-failed ()
  "Case git-gutter-mode disabled"
  (with-temp-buffer
    (git-gutter-mode 1)
    (should-not git-gutter-mode))

  (let ((default-directory nil))
    (git-gutter-mode 1)
    (should-not git-gutter-mode))

  (let ((default-directory "foo"))
    (git-gutter-mode 1)
    (should-not git-gutter-mode))

  (when (file-directory-p ".git") ;; #36
    (with-current-buffer (find-file-noselect ".git/config")
      (git-gutter-mode 1)
      (should-not git-gutter-mode))))

(ert-deftest global-git-gutter-mode-success ()
  "Case global-git-gutter-mode enabled"
  (with-temporary-directory
   (lambda ()
     (vc-create-repo 'Git)
     (with-current-buffer (find-file-noselect "test.el")
       (global-git-gutter-mode 1)
       (should git-gutter-mode)))))

(ert-deftest global-git-gutter-mode-failed ()
  "Case global-git-gutter-mode disabled"

  (with-temp-buffer
    (global-git-gutter-mode t)
    (should-not git-gutter-mode))

  (let* ((git-gutter:disabled-modes '(emacs-lisp-mode))
         (buf (find-file-noselect "test-git-gutter.el")))
    (unwind-protect
        (with-current-buffer buf
          (global-git-gutter-mode t)
          (should-not git-gutter-mode))
      (kill-buffer buf))))

(ert-deftest git-gutter-git-diff-arguments ()
  "Command line options of `git diff'"

  (let ((git-gutter:diff-option "-a -b -c")
        (file "git-gutter.el"))
    (let ((got (git-gutter:git-diff-arguments file)))
      (should (equal got '("-a" "-b" "-c" "--" "git-gutter.el"))))

    (let* ((git-gutter:start-revision "HEAD")
           (got (git-gutter:git-diff-arguments file)))
      (should (equal got '("-a" "-b" "-c" "HEAD" "--" "git-gutter.el"))))))

(ert-deftest git-gutter-hg-diff-arguments ()
  "Command line options of `hg diff'"

  (let ((git-gutter:mercurial-diff-option "-a -b -c")
        (file "git-gutter.el"))
    (let ((got (git-gutter:hg-diff-arguments file)))
      (should (equal got '("-a" "-b" "-c" "git-gutter.el"))))

    (let* ((git-gutter:start-revision "30000")
           (got (git-gutter:hg-diff-arguments file)))
      (should (equal got '("-a" "-b" "-c" "-r" "30000" "git-gutter.el"))))))

(ert-deftest git-gutter-bzr-diff-arguments ()
  "Command line options of `bzr diff'"

  (let ((git-gutter:bazaar-diff-option "-a -b -c")
        (file "git-gutter.el"))
    (let ((got (git-gutter:bzr-diff-arguments file)))
      (should (equal got '("-a" "-b" "-c" "git-gutter.el"))))

    (let* ((git-gutter:start-revision "30000")
           (got (git-gutter:bzr-diff-arguments file)))
      (should (equal got '("-a" "-b" "-c" "-r" "30000" "git-gutter.el"))))))

(ert-deftest git-gutter-read-header ()
  "Read header of diff hunk"

  (let ((got (git-gutter:read-hunk-header "@@ -658,31 +688,30 @@")))
    (should (= (nth 0 got) 658))
    (should (= (nth 1 got) 31))
    (should (= (nth 2 got) 688))
    (should (= (nth 3 got) 30)))

  (let ((got (git-gutter:read-hunk-header "@@ -100 +200 @@")))
    (should (= (nth 0 got) 100))
    (should (= (nth 1 got) 1))
    (should (= (nth 2 got) 200))
    (should (= (nth 3 got) 1))))

(ert-deftest git-gutter-show-backends ()
  "Show only handled backends."

  (let ((git-gutter:handled-backends '(bzr))
        (expected "Bzr"))
    (should (string= (git-gutter:show-backends) expected)))

  (let ((git-gutter:handled-backends '(git hg bzr))
        (expected "Git/Hg/Bzr"))
    (should (string= (git-gutter:show-backends) expected))))

;; `clone-buffer' copies the buffer-local `kill-buffer-hook' of an
;; indirect buffer into a buffer that has no base buffer.
(ert-deftest git-gutter:kill-indirect-buffer-without-base ()
  "Killing a clone of an indirect buffer does not signal an error."
  (let* ((base (generate-new-buffer "git-gutter-base"))
         (indirect (make-indirect-buffer
                    base (generate-new-buffer-name "git-gutter-indirect")))
         (clone (with-current-buffer indirect (clone-buffer))))
    (unwind-protect
        (progn
          (should-not (buffer-base-buffer clone))
          (kill-buffer clone)
          (should-not (buffer-live-p clone)))
      (kill-buffer base))))

;; Staging tests: commit a file with lines 1..10, change line 5,
;; stage that hunk with `git-gutter:stage-hunk', and check the index.

(defun git-gutter-test:git (&rest args)
  "Run git with ARGS in `default-directory'; signal an error on failure."
  (with-temp-buffer
    (unless (zerop (apply #'process-file "git" nil t nil
                          "-c" "user.name=test" "-c" "user.email=test@example.com"
                          args))
      (error "git %S failed: %s" args (buffer-string)))
    (buffer-string)))

(defun git-gutter-test:stage-line-5 (file)
  "Change line 5 of FILE, stage the hunk with git-gutter, return `git diff --cached'."
  (let ((buf (find-file-noselect file)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (forward-line 4)
          (delete-region (point) (line-end-position))
          (insert "FIVE")
          (save-buffer)
          (git-gutter-mode 1)
          (git-gutter)
          (with-timeout (10 (error "git-gutter did not finish"))
            (while (not git-gutter:enabled)
              (accept-process-output nil 0.1)))
          (goto-char (point-min))
          (forward-line 4)
          (let ((git-gutter:ask-p nil))
            (git-gutter:stage-hunk))
          (git-gutter-test:git "diff" "--cached" "--no-color"))
      (with-current-buffer buf (set-buffer-modified-p nil))
      (kill-buffer buf))))

(ert-deftest git-gutter:stage-hunk-in-subdirectory ()
  "Stage a hunk of a file that is not in the top directory of the repository."
  (with-temporary-directory
   (lambda ()
     (git-gutter-test:git "init" "-q")
     (make-directory "sub")
     (with-temp-file "sub/f.txt"
       (dotimes (i 10) (insert (format "%d\n" (1+ i)))))
     (git-gutter-test:git "add" "sub/f.txt")
     (git-gutter-test:git "commit" "-q" "-m" "init")
     (let ((cached (git-gutter-test:stage-line-5
                    (expand-file-name "sub/f.txt"))))
       (should (string-match-p "^\\+FIVE\r?$" cached))))))

(ert-deftest git-gutter:stage-hunk-in-bare-repository ()
  "Stage a hunk when GIT_DIR and GIT_WORK_TREE point to a bare repository."
  (with-temporary-directory
   (lambda ()
     (let ((git-dir (expand-file-name "repo.git"))
           (work-tree (file-name-as-directory (expand-file-name "home")))
           (process-environment (copy-sequence process-environment)))
       (git-gutter-test:git "init" "-q" "--bare" git-dir)
       (setenv "GIT_DIR" git-dir)
       (setenv "GIT_WORK_TREE" work-tree)
       (make-directory (expand-file-name ".config/x" work-tree) t)
       (let ((default-directory work-tree))
         (with-temp-file ".config/x/f.txt"
           (dotimes (i 10) (insert (format "%d\n" (1+ i)))))
         (git-gutter-test:git "add" ".config/x/f.txt")
         (git-gutter-test:git "commit" "-q" "-m" "init")
         (let ((cached (git-gutter-test:stage-line-5
                        (expand-file-name ".config/x/f.txt"))))
           (should (string-match-p "^\\+FIVE\r?$" cached))))))))

;; Window change hooks.  Emacs runs these hooks only during redisplay,
;; which batch mode does not do, so the tests call the hook functions
;; directly.

(defmacro git-gutter-test:with-file-in-repo (&rest body)
  "Run BODY in a buffer with `git-gutter-mode' on, visiting a committed file."
  (declare (indent 0))
  `(with-temporary-directory
    (lambda ()
      (git-gutter-test:git "init" "-q")
      (with-temp-file "f.txt" (insert "1\n"))
      (git-gutter-test:git "add" "f.txt")
      (git-gutter-test:git "commit" "-q" "-m" "init")
      (let ((buf (find-file-noselect (expand-file-name "f.txt"))))
        (unwind-protect
            (with-current-buffer buf
              (git-gutter-mode 1)
              ,@body)
          (kill-buffer buf))))))

(defmacro git-gutter-test:count-git-gutter-calls (&rest body)
  "Run BODY with `git-gutter' replaced by a counter; return the count."
  (declare (indent 0))
  `(let ((calls 0))
     (cl-letf (((symbol-function 'git-gutter)
                (lambda () (setq calls (1+ calls)))))
       ,@body)
     calls))

(ert-deftest git-gutter:window-change-hooks-installed ()
  "`git-gutter-mode' adds and removes its buffer-local window change hooks."
  (git-gutter-test:with-file-in-repo
    (should (memq #'git-gutter:window-buffer-change-function
                  window-buffer-change-functions))
    (should (memq #'git-gutter:window-selection-change-function
                  window-selection-change-functions))
    (git-gutter-mode -1)
    (should-not (memq #'git-gutter:window-buffer-change-function
                      window-buffer-change-functions))
    (should-not (memq #'git-gutter:window-selection-change-function
                      window-selection-change-functions))))

(ert-deftest git-gutter:window-selection-change-function ()
  "Update only for the selected window, and only with `git-gutter-mode' on."
  (git-gutter-test:with-file-in-repo
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (let ((selected (selected-window))
            (other (split-window-right)))
        (set-window-buffer other (current-buffer))
        (should (= 1 (git-gutter-test:count-git-gutter-calls
                       (git-gutter:window-selection-change-function selected))))
        (should (= 0 (git-gutter-test:count-git-gutter-calls
                       (git-gutter:window-selection-change-function other))))
        (git-gutter-mode -1)
        (should (= 0 (git-gutter-test:count-git-gutter-calls
                       (git-gutter:window-selection-change-function selected))))))))

(ert-deftest git-gutter:window-buffer-change-function ()
  "Update when a window starts showing a buffer with `git-gutter-mode' on."
  (git-gutter-test:with-file-in-repo
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (should (= 1 (git-gutter-test:count-git-gutter-calls
                     (git-gutter:window-buffer-change-function (selected-window)))))
      (git-gutter-mode -1)
      (should (= 0 (git-gutter-test:count-git-gutter-calls
                     (git-gutter:window-buffer-change-function (selected-window))))))))

;; `git-gutter:view-for-unchanged' puts an overlay on every line outside
;; the hunks: the unchanged sign, or a blank followed by the separator.

(defun git-gutter-test:unchanged-overlay-lines (hunks)
  "Lines 1..10 of a buffer that get an unchanged overlay for HUNKS."
  (with-temp-buffer
    (dotimes (i 10) (insert (format "%d\n" (1+ i))))
    (git-gutter:view-for-unchanged
     (mapcar (lambda (range)
               (make-git-gutter-hunk :type 'modified :content ""
                                     :start-line (car range)
                                     :end-line (cdr range)))
             hunks))
    (sort (mapcar (lambda (ov) (line-number-at-pos (overlay-start ov)))
                  (seq-filter (lambda (ov) (overlay-get ov 'git-gutter))
                              (overlays-in (point-min) (point-max))))
          #'<)))

(ert-deftest git-gutter:view-for-unchanged-lines ()
  "The unchanged sign goes on the lines outside the hunks."
  (let ((git-gutter:unchanged-sign ".")
        (git-gutter:separator-sign nil))
    (should (equal (git-gutter-test:unchanged-overlay-lines '((3 . 4) (7 . 7)))
                   '(1 2 5 6 8 9 10)))
    (should (equal (git-gutter-test:unchanged-overlay-lines '((1 . 1) (10 . 10)))
                   '(2 3 4 5 6 7 8 9)))
    (should (equal (git-gutter-test:unchanged-overlay-lines nil)
                   '(1 2 3 4 5 6 7 8 9 10)))))

(ert-deftest git-gutter:view-for-unchanged-separator-only ()
  "With only a separator, unchanged lines still get an overlay."
  (let ((git-gutter:unchanged-sign nil)
        (git-gutter:separator-sign "|"))
    (should (equal (git-gutter-test:unchanged-overlay-lines '((3 . 4)))
                   '(1 2 5 6 7 8 9 10)))))

;;; test-git-gutter.el end here
