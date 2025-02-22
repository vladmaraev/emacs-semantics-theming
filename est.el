
;; Copyright: FSF

;; Author: Jean-Philippe Bernardy <jeanphilippe.bernardy@gmail.com>
;; Maintainer: Jean-Philippe Bernardy <jeanphilippe.bernardy@gmail.com>
;; URL: https://github.com/jyp/emacs-semantics-theming
;; Created: January 2021
;; Keywords: theming
;; Package-Requires: ((emacs "26") (dash "2.17.0"))
;; Version: 1

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This file attempts to est ablish an Emacs Semantically-sound
;; Theming foundation. The goal is to provide a visually pleasant and
;; semantically coherent meta-theme, which is easy to customize (with
;; as little as a palette of six colors).
;;
;; This a achieved through a number of articulated parts:
;;
;; - a small layer of customisation on top of standard emacs
;; customisation. 1. We can record customs are belonging to a set
;; which must be re-evaluated. This means that a customs can depend on
;; each others (possibly in a long chain of dependencies.) 2. Instead
;; of customizing faces directly, we can customize their
;; *specs*. 3. `est-reevaluate' re-evaluates all the special customs,
;; including face specs, and reapply them to faces.
;;
;; - a small set of face(specs) which are assigned a meaning (use
;; customize-apropos-faces est- for a list). However, these
;; face(specs) are defined using the above customization system, which
;; means that it's often better to customize them indirectly, by
;; customizing the variables (colors) which occur in their spec
;; standard value. The default for these faces are are meant to define
;; a visually coherent set of faces.
;; Besides, sometimes standard emacs faces are incorporated in the set
;; (eg. `shadow') --- and in this case their specs
;; are customised using the above mechanism.
;;
;; - a theme (`est-style') which defines a large number of (regular)
;; faces as inheriting those from the above set. This means that it
;; suffices to customize the small set (via customizing an even
;; smaller set of variables).
;;
;; - a set of examples configurations. They configure a minimal
;; palette of six colors, eventually theming everything.


;;; Code:

(require 'color)
(require 'dash)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Customisation infrastructure

(defvar est-customs nil "List of customs to re-evaluate when applying est-theming")
(defvar est-faces   nil "List of faces to reset when applying est-theming")
(setq est-customs nil
      est-faces nil)

(defmacro est-defcustom (symbol standard docstring &rest args)
  "Define SYMBOL with STANDARD valued and DOCSTRING, with ARGS.
Also register SYMBOL for evaluation by `est-reevaluate'."
  (declare (doc-string 3) (debug (name body)))
  `(progn
     (push ',symbol est-customs)
     (defcustom ,symbol ,standard ,docstring :group 'est ,@args)
     ))

(defmacro est-stealcustom (file symbol standard)
  "Re-define the standard value for SYMBOL as STANDARD.
Also register SYMBOL for evaluation by `est-reevaluate'. SYMBOL
should be originally defined in FILE, together with its doc,
groups, etc.  So"
  (declare (doc-string 3) (debug (name body)))
  `(with-eval-after-load ,file
     (push ',symbol est-customs)
     (put ',symbol 'standard-value (purecopy (list ',standard)))
     (set ',symbol ,standard)))

(defun est-spec-symbol (face-symbol)
  (intern (concat (symbol-name face-symbol) "-spec")))

(defmacro est-defface (face-symbol spec doc &rest args)
  (let ((spec-symbol (est-spec-symbol face-symbol)))
    `(progn
       (custom-declare-variable ',spec-symbol ',spec ,doc :group 'est :type 'sexp ,@args)
       (push ',spec-symbol est-customs)
       (push ',face-symbol est-faces))))

(defmacro est-stealface (face-symbol spec &rest args)
  `(est-defface ,face-symbol ,spec (face-documentation ',face-symbol) ,@args))

(defun est-reevaluate ()
  ;; FIXME: est-customs should really be sorted according to their
  ;; dependencies. But we don't have them. In general it depends on
  ;; the free variables in the custom standard values. For now, we do the
  ;; simple thing of assuming that they are declared in order of
  ;; dependencies.
  (dolist (symbol (reverse est-customs))
    (custom-reevaluate-setting symbol))
  (dolist (face-symbol est-faces)
    ;; est-  faces are not controlled by custom. est- face specs are. So override the faces here.
    (face-spec-set face-symbol (purecopy (eval (est-spec-symbol face-symbol))) 'face-defface-spec)))

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Color manipulation

(defcustom est-gamma 1.5
  "Gamma correction parameter for `est'.
2.2 is the standard value but for light palettes tends to yield
too bright colors due to too accurate color addition."
  :group 'est :type 'float)

(defun est-scale-color (scale col)
  "Multiply every entry in COL by SCALE."
  (--map (* scale it) col))

(defun est-add-color (a b)
  "Add entries of A and B indexwise."
  (-zip-with '+ a b))

(defun est-sub-color (a b)
  "Subtract entries of B from A indexwise."
  (-zip-with '- a b))

(defun est-exp-gamma (x)
  "Apply gamma correction to X."
  (exp (* (log x) est-gamma)))

(defun est-exp-inv-gamma (x)
  "Unapply gamma correction to X."
  (exp (/ (log x) est-gamma)))

(defun est-clamp (components)
  "Make sure each of the COMPONENTS is in the [0,1] interval."
  (--map (max 0.0 (min 1.0 it)) components))

(defun est-over-composite (base addition)
  "Composite of ADDITION over BASE.
With premultiplied colors, without gamma correction."
  (let ((alpha (car addition)))
    (est-add-color (est-scale-color (- 1.0 alpha) base) addition)
    ))

(defun est-what-under-composite (over addition)
  "What was under OVER before ADDITION was painted?"
  (let ((alpha (car addition)))
    (est-scale-color (/ 1.0 (- 1.0 alpha))
                 (est-sub-color over addition))))

(defun est-argb-to-hex (components)
  "Encode COMPONENTS in the (a r g b) format to hex name.
Input is assumed to be alpha-premultiplied and gamma corrected."
  (pcase-let ((`(,alpha . ,rgb) components))
    (apply 'color-rgb-to-hex (-map 'est-exp-inv-gamma (est-clamp (est-scale-color (/ 1 alpha) rgb))))))

(defun est-alpha-name (alpha name)
  "Decode a pair of ALPHA color NAME to (a r g b) format.
Includes applying gamma and premultiply."
  (cons alpha (est-scale-color alpha (-map 'est-exp-gamma (color-name-to-rgb name)))))

(defun est-paint-over (base alpha addition)
"Paint ADDITION over BASE with opacity ALPHA.
Inputs colors are names."
  (est-argb-to-hex
   (est-over-composite (est-alpha-name 1.0   base)
                       (est-alpha-name alpha addition))))

(defun est-scrape-paint (base alpha addition)
"Recover what yielded BASE after painting ADDITION opacity ALPHA.
Inputs colors are names."
  (est-argb-to-hex
   (est-what-under-composite (est-alpha-name 1.0   base)
                             (est-alpha-name alpha addition))))

(defun est-color-hue (name)
  "Set HUE of BASE."
  (pcase-let ((`(,l ,a ,b)
               (apply 'color-srgb-to-lab (color-name-to-rgb name))))
    (atan a b)))

(defun est-color-lightness (name)
  (car (apply 'color-srgb-to-lab (color-name-to-rgb name))))

;;;;;;;;;;;
;; Colors


(defcustom est-color-fg-default "#3e4759"
  "Default foreground color." :type 'color :group 'est)

(defcustom est-color-bg-default "#ffffff"
"Default background color."
:type 'color :group 'est)

(defcustom est-color-fg-salient "#2056a2"
  "Color of persistent accents.
It is suitable for links and names which can be followed, such as
directories, required elisp modules, etc." :type 'color :group 'est)

(defcustom est-color-fg-popout "#00e0ff"
"Accented color which should be easy to spot.
It is used mostly to attract attention immediately relevant
portions of the display, whose relevant state is transient.
Transience can be as low as isearch matches, balanced parens or
high TODOs, etc.  Attention can be grabbed using a remarkable hue
and high staturation." :type 'color :group 'est)

(defcustom est-color-fg-critical "#FF2F00"
"Color indicating that urgent attention is required.
Not taking care of the issue will most likely lead to problems
down the road: this is for critical problems, and can be
indicated with extra strong, even disturbing contrast, saturation
and a red hue." :type 'color :group 'est)

(defcustom est-color-bg-subtle "#eef1f6"
"A background color sublty different from the default.
This can be used for slight emphasis, or to delineate areas, such
as the region.  This color can even be used exceptionally as
foreground in case the text is not meant to be read, for example
to display weak separators."  :type 'color :group 'est)

(defcustom est-color-bg-selected "#e5e9f0"
"A background color which is notably different from the default.
Still, it should be contrasting with all foreground colors to
enable easy reading.  It is used for to indicate selected menu
items, or delinate areas with stronger emphasis." :type 'color
:group 'est)


(defcustom est-taint-vc-base "#0000FF"
"A taint to indicate base stuff in VC contexts.
This is not used directly in faces, but blended with various background
colors. So it is fine to use saturated bright colors here." :type 'color :group
'est)

(defcustom est-taint-vc-third "#FFFF00"
"A taint to indicate third-party stuff in VC contexts.
This is not used directly in faces, but blended with various background
colors. So it is fine to use saturated bright colors here." :type 'color :group
'est)

(defcustom est-taint-vc-added "#00FF00"
"A taint to indicate added stuff in VC contexts.
This is not used directly in faces, but blended with various background
colors. So it is fine to use saturated bright colors here." :type 'color :group
'est)


(defcustom est-taint-vc-removed "#FF0000"
"A taint to indicate removed stuff in VC contexts.
This is not used directly in faces, but blended with various background
colors.  So it is fine to use saturated bright colors here."
:type 'color :group 'est)

(est-defcustom
 est-is-dark-mode (< (est-color-lightness est-color-bg-default) 40)
 "non-nil if this is this a dark background mode")

(est-stealcustom 'pdf-view pdf-view-midnight-colors (cons est-color-fg-default est-color-bg-default))

(est-defcustom est-accent-lightness (+ (* 0.6 (est-color-lightness est-color-fg-default))
                                       (* 0.4 (est-color-lightness est-color-bg-default)))
"Lightness for highlight colors.
Usually somewhat not as bright/contrasted as that of the default
fg."  :type 'float :group 'est)

(defun est-color-lab (l a b)
  (apply 'color-rgb-to-hex (est-clamp (color-lab-to-srgb l a b))))

(defun est-color-lch (lightness chroma hue)
  (est-color-lab lightness (* chroma (cos hue)) (* chroma (sin hue))))

(defcustom est-accent-chroma 50 "amount of chroma for accent colors")
(est-defcustom est-hue-fundamental   (est-color-hue est-color-fg-popout) "fundamental accent hue")
(est-defcustom est-hue-complementary (+ est-hue-fundamental float-pi) "complementary accent hue")
(est-defcustom est-hue-analogous1   (+ est-hue-fundamental (/ float-pi 3)) "analogous1 accent hue")
(est-defcustom est-hue-analogous2   (- est-hue-fundamental (/ float-pi 3)) "analogous2 accent hue")
(est-defcustom est-hue-coanalogous1 (+ est-hue-complementary (/ float-pi 3)) "coanalogous1 accent hue")
(est-defcustom est-hue-coanalogous2 (- est-hue-complementary (/ float-pi 3)) "coanalogous2 accent hue")

(est-defface est-fg-complementary `((t :foreground ,(est-color-lch est-accent-lightness est-accent-chroma est-hue-complementary))) "todo")
(est-defface est-fg-analogous1 `((t :foreground ,(est-color-lch est-accent-lightness est-accent-chroma est-hue-analogous1))) "todo")
(est-defface est-fg-analogous2 `((t :foreground ,(est-color-lch est-accent-lightness est-accent-chroma est-hue-analogous2))) "todo")
(est-defface est-fg-coanalogous1 `((t :foreground ,(est-color-lch est-accent-lightness est-accent-chroma est-hue-coanalogous1))) "todo")
(est-defface est-fg-coanalogous2 `((t :foreground ,(est-color-lch est-accent-lightness est-accent-chroma est-hue-coanalogous2))) "todo")

;;;;;;;;;;;;;;;;;;;;;;;
;; Hack against hacks

;; org-mode tries to be clever regarding foreground color. But it is not. Shut it down:
(with-eval-after-load 'org
  (fset 'org-find-invisible-foreground (lambda () nil)))

(setq hi-lock-face-defaults ;; not a defcustom: simply override this. (The defaults have anti-semantics names (yellow, etc.))
      '("est-fg-analogous1" "est-fg-analogous2"  "est-fg-coanalogous1" "est-fg-coanalogous2" "est-fg-complementary"))
(setq boon-hl-face-defaults
      '(est-fg-analogous1 est-fg-analogous2  est-fg-coanalogous1 est-fg-coanalogous2 est-fg-complementary))

;;;;;;;;;;;;;;;;;;;;;;;;;

;; (est-defcustom est-color-fg-yellow (est-color-lch est-accent-lightness est-accent-chroma est-hue-yellow) "yellow fg color")
;; (est-defcustom est-color-fg-pink   (est-color-lch est-accent-lightness est-accent-chroma est-hue-pink) "pink fg color")
;; (est-defcustom est-color-fg-teal   (est-color-lch est-accent-lightness est-accent-chroma est-hue-teal) "teal fg color")
;; (est-defcustom est-color-fg-blue   (est-color-lch est-accent-lightness est-accent-chroma est-hue-blue) "blue fg color")
;; (est-defcustom est-color-fg-green  (est-color-lch est-accent-lightness est-accent-chroma est-hue-green) "green fg color")
;; (est-defcustom est-color-fg-violet (est-color-lch est-accent-lightness est-accent-chroma est-hue-violet) "violet fg color")
;; (est-defcustom est-color-fg-red    (est-color-lch est-accent-lightness est-accent-chroma est-hue-red) "red fg color")
;; (est-defcustom est-color-fg-cyan   (est-color-lch est-accent-lightness est-accent-chroma est-hue-cyan) "cyan fg color")
;; (est-defface est-fg-yellow `((t :foreground ,est-color-fg-yellow)) "yellow fg")
;; (est-defface est-fg-pink   `((t :foreground ,est-color-fg-pink)) "pink fg")
;; (est-defface est-fg-teal   `((t :foreground ,est-color-fg-teal)) "teal fg")
;; (est-defface est-fg-blue   `((t :foreground ,est-color-fg-blue)) "blue fg")
;; (est-defface est-fg-green  `((t :foreground ,est-color-fg-green)) "green fg")
;; (est-defface est-fg-violet `((t :foreground ,est-color-fg-violet)) "violet fg")
;; (est-defface est-fg-red	   `((t :foreground ,est-color-fg-red)) "red fg")
;; (est-defface est-fg-cyan   `((t :foreground ,est-color-fg-cyan)) "cyan fg")

(est-defcustom est-color-bg-elusive   (est-paint-over  est-color-bg-default 0.5  est-color-bg-subtle)  "bg. elusive" :type 'color)
(est-defcustom est-color-bg-hilight1  (est-paint-over  est-color-bg-default 0.15 est-color-fg-popout)  "bg. highlight 1st kind" :type 'color)
(est-defcustom est-color-bg-hilight2  (est-paint-over  est-color-bg-default 0.15 est-color-fg-salient) "bg. highlight 2nd kind" :type 'color)
(est-defcustom est-color-bg-selected-hilight1  (est-paint-over  est-color-bg-selected 0.15 est-color-fg-popout)  "bg. selected highlight 1st kind" :type 'color)
(est-defcustom est-color-bg-selected-hilight2  (est-paint-over  est-color-bg-selected 0.15 est-color-fg-salient) "bg. selected highlight 2nd kind" :type 'color)
(est-defcustom est-color-fg-shadowed  (est-paint-over  est-color-fg-default 0.6 est-color-bg-default)  "de-selected/disabled menu options" :type 'color)
(est-defcustom est-color-fg-faded     (est-paint-over  est-color-fg-default 0.2 est-color-bg-default)  "de-emphasized (comments, etc.)" :type 'color)
(est-defcustom est-color-fg-emph      (est-scrape-paint est-color-fg-default 0.2 est-color-bg-default) "subtle emphasis" :type 'color)

(est-stealcustom 'hl-paren hl-paren-colors
               (list est-color-fg-salient
                     (est-paint-over est-color-fg-salient 0.25 est-color-fg-emph)
                     (est-paint-over est-color-fg-salient 0.5 est-color-fg-emph)
                     (est-paint-over est-color-fg-salient 0.75 est-color-fg-emph)))

;;;;;;;;;;;;;;;
;; Faces


(est-defface est-separator `((t :foreground ,est-color-bg-selected))
             "Face for separators (such as --------)")

(est-defface est-choice `((t :background ,est-color-bg-selected :extend t))
  "Background face for the current selection.
(in completions frameworks, but also magit, etc.) Not the region!")

(est-defface est-highlight-1 `((t :background ,est-color-bg-hilight1))
  "Face for semi-transient highlights. The meaning is similar to
`est-popout', but for backgrounds (when changing the foreground
color is somehow inappropriate).")

(est-defface est-highlight-2 `((t :background ,est-color-bg-hilight2))
  "Face for secondary highlights")


(est-defface est-choice-highlight-1 `((t :background ,est-color-bg-selected-hilight1))
  "Face for semi-transient highlights over `est-choice'. The meaning is similar to
`est-popout', but for backgrounds (when changing the foreground
color is somehow inappropriate).")

(est-defface est-choice-highlight-2 `((t :background ,est-color-bg-selected-hilight2))
  "Face for secondary highlights over `est-choice'")

(est-defface est-critical `((t :foreground ,est-color-fg-critical))
  "Critical face is for information that requires immediate action.
  See also `est-color-fg-critical'.")

(est-defface est-popout `((t :foreground ,est-color-fg-popout))
  "Popout face is used for information that needs attention.
See also `est-color-fg-popout'.")

(est-defface est-emph `((t :foreground ,est-color-fg-emph))
  "A mild emphasis face.
This roughly corresponds to italics in mainstream typsetting
practice. By defaut the emphasis effect is achieved by using the
`est-color-fg-emph' color, which is by default slightly more
contrasted than the default color.  Besides, italics do not mesh
well with monospace fonts.")


(est-defface est-strong `((t :inherit (bold est-emph)))
  "A face with stronger emphasis than `est-emph'.
Accordingly it is used more sparingly. By default the effect is
achieved by using a bold weight together with a higher constrast
(`est-color-fg-emph').")

(est-defface est-salient `((t :foreground ,est-color-fg-salient))
  "Salient face is used for information of same urgency,
but different nature than regular text. See also
`est-color-fg-salient'.")

(est-defface est-faded `((t :foreground ,est-color-fg-faded))
  "Faded face is for information that is less important.
It is achieved by using the same hue as the default foreground
color, but with a lesser contrast. It can be used for comments
and secondary information.")

(est-defface est-subtle `((t :background ,est-color-bg-subtle))
  "Subtle face is used to suggest a physical area on the screen.
  See also `est-color-bg-subtle.'")

(est-defface est-elusive `((t :background ,est-color-bg-elusive))
  "even more subltle face is used to suggest a physical area on the screen.
  See also `est-color-bg-elusive.'")


(est-defface est-heading-0 `((t :height 1.5 :inherit est-heading)) "Face for page-level headings (titles)")
(est-defface est-heading-1 `((t :height 1.3 :inherit  est-heading)) "Face for level 1 headings")
(est-defface est-heading-2 `((t :height 1.15 :inherit est-heading)) "Face for level 2 headings")
(est-defface est-heading-3 `((t :height 1.1 :inherit est-heading)) "Face for level 3 headings")
(est-defface est-heading   `((t :inherit bold)) "Face for level 4 headings and below")

(est-defface est-frame-title
             `((t :extend t :background ,est-color-fg-salient :weight bold :foreground ,est-color-bg-default :height 1.7 :box (:line-width 40 :color ,est-color-fg-salient)))
             "Frame title; presentations, etc.")

(est-defface est-invisible `((t :foreground ,est-color-bg-default)) "Face for invisible text")

(est-stealface default  `((t :foreground ,est-color-fg-default :background ,est-color-bg-default)))
(est-stealface cursor   `((t :background ,est-color-fg-default)))
(est-stealface shadow   `((t :foreground ,est-color-fg-shadowed)))
(est-stealface mode-line           `((t :overline ,est-color-fg-faded :inherit est-choice)))
(est-stealface mode-line-inactive  `((t :overline ,est-color-fg-faded)))


(est-stealface ediff-current-diff-face-Ancestor `((t :extend t :background ,(est-paint-over est-color-bg-selected 0.1 est-taint-vc-base))))
(est-stealface ediff-current-diff-face-A        `((t :extend t :background ,(est-paint-over est-color-bg-selected 0.1 est-taint-vc-added))))
(est-stealface ediff-current-diff-face-B        `((t :extend t :background ,(est-paint-over est-color-bg-selected 0.1 est-taint-vc-removed))))
(est-stealface ediff-current-diff-face-C        `((t :extend t :background ,(est-paint-over est-color-bg-selected 0.1 est-taint-vc-third))))
(est-stealface ediff-fine-diff-face-Ancestor    `((t           :background ,(est-paint-over est-color-bg-selected 0.2 est-taint-vc-base))))
(est-stealface ediff-fine-diff-face-A           `((t           :background ,(est-paint-over est-color-bg-selected 0.2 est-taint-vc-added))))
(est-stealface ediff-fine-diff-face-B           `((t           :background ,(est-paint-over est-color-bg-selected 0.2 est-taint-vc-removed))))
(est-stealface ediff-fine-diff-face-C           `((t           :background ,(est-paint-over est-color-bg-selected 0.2 est-taint-vc-third))))
(est-stealface ediff-odd-diff-face-Ancestor     `((t :extend t :background ,(est-paint-over est-color-bg-subtle   0.1 est-taint-vc-base))))
(est-stealface ediff-odd-diff-face-A            `((t :extend t :background ,(est-paint-over est-color-bg-subtle   0.1 est-taint-vc-added))))
(est-stealface ediff-odd-diff-face-B            `((t :extend t :background ,(est-paint-over est-color-bg-subtle   0.1 est-taint-vc-removed))))
(est-stealface ediff-odd-diff-face-C            `((t :extend t :background ,(est-paint-over est-color-bg-subtle   0.1 est-taint-vc-third))))
(est-stealface ediff-even-diff-face-Ancestor    `((t :extend t :background ,(est-paint-over est-color-bg-default  0.1 est-taint-vc-base))))
(est-stealface ediff-even-diff-face-A           `((t :extend t :background ,(est-paint-over est-color-bg-default  0.1 est-taint-vc-added))))
(est-stealface ediff-even-diff-face-B           `((t :extend t :background ,(est-paint-over est-color-bg-default  0.1 est-taint-vc-removed))))
(est-stealface ediff-even-diff-face-C           `((t :extend t :background ,(est-paint-over est-color-bg-default  0.1 est-taint-vc-third))))


(defface est-force-fixed-pitch '((t)) "Face for explicitly fixed
pitch. Can be useful if the default face is variable pitch.")

;; est-customs
;;;;;;;;;;;;;;;;;;;;;;
;; Styling theme

(deftheme est-style)
(put 'est-style 'theme-settings nil) ; reset so this file can be eval'ed several times (for development)

(custom-theme-set-variables
 'est-style
 '(org-fontify-done-headline nil) ;; does not work with changing size of headlines
 '(org-fontify-todo-headline nil) ;; does not work with changing size of headlines
 '(org-cycle-level-faces nil)
 )

(custom-theme-set-faces
 'est-style
   '(est-magit-selection ((t :inherit est-salient)))
 
   '(buffer-menu-buffer ((t :inherit est-salient)))
   '(success ((t :inherit est-strong)))
   '(warning ((t :inherit (est-salient bold))))

   '(error   ((t :inherit est-critical)))
   '(link    ((t :inherit (est-salient underline))))
   '(link-visited ((t :inherit link)))
   '(match   ((t :inherit est-popout))) ;;  "Face for matched substrings (helm, ivy, etc.) "

   '(region  ((t :inherit est-subtle)))
   '(secondary-selection ((t :inherit est-subtle)))
   '(fringe  ((t :inherit est-faded)))


   '(header-line         ((t :inherit est-heading)))
   '(highlight           ((t :inherit est-choice)))
   '(hl-line             ((t :inherit est-subtle)))
   '(lazy-highlight      ((t :inherit est-subtle)))
   '(minibuffer-prompt   ((t :inherit est-emph)))
   '(show-paren-match    ((t :inherit est-popout)))
   '(show-paren-mismatch ((t :inherit est-critical)))
   '(trailing-whitespace ((t :inherit est-subtle)))

   '(avy-background-face ((t :inherit shadow)))
   '(avy-lead-face       ((t :inherit est-popout)))
   '(avy-lead-face-0     ((t :inherit est-emph)))
   '(avy-lead-face-1     ((t :inherit est-emph)))
   '(avy-lead-face-2     ((t :inherit est-emph)))
   
   '(boon-modeline-ins ((t :inherit est-choice-highlight-1)))
   '(boon-modeline-spc ((t :inherit est-choice-highlight-2)))
   '(boon-modeline-cmd ((t :inherit est-subtle)))
   '(boon-modeline-off ((t :inherit error)))

   '(custom-group-tag-1       ((t :inherit est-heading-1)))
   '(custom-group-tag         ((t :inherit est-heading-2)))
   '(custom-variable-tag      ((t :inherit est-heading)))
   '(custom-state             ((t :inherit est-emph)))
   '(custom-changed           ((t :inherit est-highlight-1)))
   '(custom-modified          ((t :inherit est-highlight-1)))
   '(custom-invalid           ((t :inherit (est-critical est-subtle))))
   '(custom-rogue             ((t :inherit (est-critical est-subtle))))
   '(custom-set               ((t :inherit est-highlight-2)))
   '(custom-variable-obsolete ((t :inherit est-faded)))

   '(company-preview            ((t :inherit est-choice)))
   '(company-preview-common     ((t :inherit (est-emph  company-preview))))
   '(company-preview-search     ((t :inherit (est-match company-preview))))
   '(company-scrollbar-bg       ((t :inherit est-subtle)))
   '(company-tooltip            ((t :inherit est-subtle)))
   '(company-tooltip-selection  ((t :inherit est-choice)))
   '(company-tooltip-common     ((t :inherit est-emph)))
   '(company-tooltip-annotation ((t :inherit shadow)))
   '(company-scrollbar-bg       ((t :inverse-video t :inherit est-shadow)))
   '(company-scrollbar-fg       ((t :inverse-video t :inherit est-emph)))

   '(completions-common-part      ((t :inherit match)))
   '(completions-first-difference ((t)))

   '(dired-directory ((t :inherit est-salient)))
   '(dired-flagged   ((t :inherit est-popout)))

   '(diff-file-header  ((t :inherit est-heading-3)))
   '(diff-header       ((t :inherit est-heading-4)))
   '(diff-added           ((t :inherit ediff-even-diff-face-A)))
   '(diff-removed         ((t :inherit ediff-even-diff-face-B)))



   '(eshell-prompt        ((t :inherit est-strong)))
   '(eshell-ls-directory  ((t :inherit dired-directory)))
   '(eshell-ls-symlink    ((t :inherit dired-symlink)))
   '(eshell-ls-executable ((t :inherit est-popout)))
   '(eshell-ls-readonly   ((t :inherit default)))
   '(eshell-ls-unreadable ((t :inherit dired-warning)))
   '(eshell-ls-special    ((t :inherit dired-special)))
   '(eshell-ls-missing    ((t :inherit error)))
   '(eshell-ls-archive    ((t :inherit est-faded)))
   '(eshell-ls-backup     ((t :inherit est-faded)))
   '(eshell-ls-product    ((t :inherit est-faded)))
   '(eshell-ls-clutter    ((t :inherit error)))

   '(font-latex-sectioning-1-face   ((t :inherit est-heading-1)))
   '(font-latex-sectioning-2-face   ((t :inherit est-heading-2)))
   '(font-latex-sectioning-3-face   ((t :inherit est-heading-3)))
   '(font-latex-sectioning-4-face   ((t :inherit est-heading)))
   '(font-latex-sectioning-5-face   ((t :inherit est-heading)))
   '(font-latex-bold-face           ((t :inherit bold)))
   '(font-latex-math-face           ((t :inherit est-salient)))
   '(font-latex-script-char-face    ((t :inherit est-salient)))
   '(font-latex-string-face         ((t :inherit est-faded)))
   '(font-latex-warning-face        ((t :inherit est-strong))) ; latex-warning face is not really a warning face!
   '(font-latex-italic-face         ((t :inherit est-emph)))
   '(font-latex-verbatim-face       ((t :inherit est-faded)))

   '(font-lock-builtin-face       ((t)))
   '(font-lock-comment-face       ((t :inherit est-faded)))
   '(font-lock-constant-face      ((t :inherit est-salient)))
   '(font-lock-function-name-face ((t :inherit est-strong)))
   '(font-lock-keyword-face       ((t :inherit est-emph)))
   '(font-lock-string-face        ((t :inherit est-faded)))
   '(font-lock-type-face          ((t)))
   '(font-lock-variable-name-face ((t)))
   '(font-lock-warning-face       ((t :inherit warning)))

   '(helm-candidate-number           ((t :inherit mode-line)))
   '(helm-candidate-number-suspended ((t :inherit (warning mode-line))))
   '(helm-ff-directory               ((t :inherit est-strong)))
   '(helm-ff-dotted-directory        ((t :inherit est-faded)))
   '(helm-ff-executable              ((t :inherit est-popout)))
   '(helm-ff-file                    ((t :inherit est-faded)))
   '(helm-ff-file-extension          ((t :inherit est-faded)))
   '(helm-ff-prefix                  ((t :inherit est-strong)))
   '(helm-grep-file                  ((t :inherit est-faded)))
   '(helm-grep-finish                ((t)))
   '(helm-grep-lineno                ((t :inherit est-faded)))
   '(helm-grep-match                 ((t :inherit match)))
   '(helm-match                      ((t :inherit match)))
   '(helm-moccur-buffer              ((t :inherit est-strong)))
   '(helm-selection                  ((t :inherit highlight)))
   '(helm-separator                  ((t :inherit est-separator)))
   '(helm-source-header              ((t :inherit est-heading)))
   '(helm-swoop-target-line-face     ((t :inherit (est-strong est-subtle))))
   '(helm-visible-mark               ((t :inherit est-strong)))
   '(helm-buffer-size                ((t :inherit est-faded)))
   '(helm-buffer-process             ((t :inherit shadow)))
   '(helm-buffer-not-saved           ((t :inherit est-popout)))
   '(helm-buffer-directory           ((t :inherit est-salient)))
   '(helm-buffer-saved-out           ((t :inherit est-critical)))

   `(help-key-binding                ((t :inherit (est-emph est-subtle) :box (:line-width (1 . -1) :color ,est-color-fg-faded))))

   '(ido-only-match ((t :inherit match)))

   '(isearch       ((t :inherit match)))
   '(isearch-fail  ((t :inherit est-faded)))

   '(info-title-1   ((t :inherit est-heading-0)))
   '(info-title-2   ((t :inherit est-heading-1)))
   '(info-title-3   ((t :inherit est-heading-2)))
   '(info-title-4   ((t :inherit est-heading-3)))
   '(info-menu-header ((t :inherit est-heading)))
   '(info-menu-star ((t :inherit est-faded)))
   '(info-node ((t :inherit italic est-emph)))

   '(ivy-action                     ((t :inherit est-faded)))
   '(ivy-completions-annotations    ((t :inherit est-faded)))
   '(ivy-confirm-face               ((t :inherit est-faded)))
   '(ivy-current-match              ((t :inherit highlight)))
   '(ivy-cursor                     ((t :inherit est-strong)))
   '(ivy-grep-info                  ((t :inherit est-strong)))
   '(ivy-grep-line-number           ((t :inherit est-faded)))
   '(ivy-match-required-face        ((t :inherit est-faded)))
   '(ivy-minibuffer-match-face-1    ((t :inherit match)))
   '(ivy-minibuffer-match-face-2    ((t :inherit match)))
   '(ivy-minibuffer-match-face-3    ((t :inherit match)))
   '(ivy-minibuffer-match-face-4    ((t :inherit match)))
   '(ivy-minibuffer-match-highlight ((t :inherit est-strong)))
   '(ivy-modified-buffer            ((t :inherit est-popout)))
   '(ivy-modified-outside-buffer    ((t :inherit est-strong)))
   '(ivy-org                        ((t :inherit est-faded)))
   '(ivy-prompt-match               ((t :inherit est-faded)))
   '(ivy-remote                     ((t)))
   '(ivy-separator                  ((t :inherit est-faded)))
   '(ivy-subdir                     ((t :inherit est-faded)))
   '(ivy-virtual                    ((t :inherit est-faded)))
   '(ivy-yanked-word                ((t :inherit est-faded)))

   '(git-commit-summary ((t :inherit est-emph)))

   '(hi-yellow ((t :inherit est-highlight-1))) ;; see also hi-lock-face-defaults
   '(hi-pink   ((t :inherit est-highlight-2)))

   '(magit-diff-hunk-heading           ((t :extend t :inherit est-heading)))
   '(magit-diff-hunk-heading-highlight ((t :extend t :inherit (est-heading est-choice))))
   '(magit-diff-context-highlight      ((t :extend t :inherit est-choice)))
   '(magit-section-heading             ((t :inherit est-heading-3)))
   '(magit-section-highlight           ((t :inherit est-choice)))
   '(magit-hash                        ((t :inherit shadow)))
   '(magit-log-author                  ((t :inherit est-faded)))
   '(magit-diff-removed                ((t :inherit diff-removed)))
   '(magit-diff-added                  ((t :inherit diff-added)))
   '(magit-tag                         ((t :inherit emph)))
   '(magit-dimmed                      ((t :inherit shadow)))
   '(magit-diff-lines-heading          ((t :inherit (est-magit-selection magit-diff-hunk-heading-highlight))))
   '(magit-diff-file-heading-selection ((t :inherit (est-magit-selection magit-diff-file-heading-highlight))))
   '(magit-diff-hunk-heading-selection ((t :inherit (est-magit-selection magit-diff-hunk-heading))))
   '(magit-section-heading-selection   ((t :inherit (est-magit-selection)))) ; doc is wrong for this face. So not assigned a section heading style (magit-section-heading)
   '(magit-diff-added-highlight   ((t :inherit ediff-current-diff-face-A)))
   '(magit-diff-removed-highlight ((t :inherit ediff-current-diff-face-B)))

   '(makefile-space               ((t :inherit warning)))

   '(orderless-match-face-0 ((t :inherit match)))
   '(orderless-match-face-1 ((t :inherit match)))
   '(orderless-match-face-2 ((t :inherit match)))
   '(orderless-match-face-3 ((t :inherit match)))

   '(org-default                  ((t :inherit variable-pitch))) ;; use (add-hook 'org-mode-hook 'buffer-face-mode) to actually use this.
   '(org-agenda-structure         ((t :inherit est-default)))
   '(org-archived                 ((t :inherit est-faded)))
   '(org-block                    ((t :inherit (est-force-fixed-pitch est-elusive))))
   '(org-block-begin-line         ((t :inherit org-block)))
   '(org-block-end-line           ((t :inherit org-block)))
   '(org-checkbox                 ((t :inherit (est-emph est-force-fixed-pitch))))
   '(org-checkbox-statistics-done ((t :inherit est-faded)))
   '(org-checkbox-statistics-todo ((t :inherit est-faded)))
   '(org-clock-overlay            ((t :inherit est-faded)))
   '(org-code                     ((t :inherit est-force-fixed-pitch)))
   '(org-column                   ((t :inherit est-faded)))
   '(org-column-title             ((t :inherit est-faded)))
   '(org-date                     ((t :inherit est-faded)))
   '(org-date-selected            ((t :inherit est-faded)))
   '(org-document-info            ((t :inherit est-default)))
   '(org-document-info-keyword    ((t :inherit est-faded)))
   '(org-document-title           ((t :inherit est-heading-0)))
   '(org-done                     ((t)))
   '(org-drawer                   ((t :inherit est-faded)))
   '(org-ellipsis                 ((t :inherit est-faded)))
   '(org-footnote                 ((t :inherit est-faded)))
   '(org-formula                  ((t :inherit est-salient)))
   '(org-headline-done            ((t :inherit est-faded)))
   '(org-hide                     ((t :inherit est-invisible))) ;; must not be fixed-pitch, otherwise org indent gives wrong results with variable pitch font.
   '(org-indent                   ((t :inherit est-invisible))) ;; must not be fixed-pitch, otherwise org indent gives wrong results with variable pitch font.
   '(org-latex-and-related        ((t :inherit est-salient)))
   '(org-level-1                  ((t :inherit est-heading-1)))
   '(org-level-2                  ((t :inherit est-heading-2)))
   '(org-level-3                  ((t :inherit est-heading-3)))
   '(org-level-4                  ((t :inherit est-heading)))
   '(org-level-5                  ((t :inherit est-heading)))
   '(org-level-6                  ((t :inherit est-heading)))
   '(org-level-7                  ((t :inherit est-heading)))
   '(org-level-8                  ((t :inherit est-heading)))
   '(org-list-dt                  ((t :inherit est-faded)))
   '(org-macro                    ((t :inherit est-faded)))
   '(org-meta-line                ((t :inherit est-faded)))
   '(org-mode-line-clock          ((t :inherit est-faded)))
   '(org-mode-line-clock-overrun  ((t :inherit warning)))
   '(org-priority                 ((t :inherit est-faded)))
   '(org-property-value           ((t :inherit est-faded)))
   '(org-ref-acronym-face         ((t (:inherit est-faded :underline t))))
   '(org-ref-cite-face            ((t (:inherit org-link))))
   '(org-ref-label-face           ((t (:inherit est-faded :underline t))))
   '(org-ref-ref-face             ((t (:inherit est-faded :underline t))))
   '(org-quote                    ((t :inherit est-faded)))
   '(org-scheduled                ((t :inherit est-faded)))
   '(org-scheduled-previously     ((t :inherit est-faded)))
   '(org-scheduled-today          ((t :inherit est-faded)))
   '(org-sexp-date                ((t :inherit est-faded)))
   '(org-special-keyword          ((t :inherit est-faded)))
   '(org-table                    ((t :inherit est-force-fixed-pitch)))
   '(org-tag                      ((t :inherit est-faded)))
   '(org-tag-group                ((t :inherit est-faded)))
   '(org-target                   ((t :inherit est-faded)))
   '(org-time-grid                ((t :inherit est-faded)))
   '(org-todo                     ((t :inherit est-popout)))
   '(org-done                     ((t :inherit est-faded)))
   '(org-upcoming-deadline        ((t :inherit est-strong)))
   '(org-verbatim                 ((t :inherit est-emph est-force-fixed-pitch)))
   '(org-verse                    ((t :inherit est-faded)))

   '(org-superstar-leading        ((t :inherit org-hide)))

   '(powerline-active0    ((t :inherit est-choice)))
   '(powerline-active1    ((t :inherit est-choice))) ;; est-highlight-1 or est-highlight-2 for extra flare
   '(powerline-active2    ((t :inherit est-choice)))
   '(powerline-inactive0  ((t :inherit est-faded)))
   '(powerline-inactive1  ((t :inherit powerline-inactive0)))
   '(powerline-inactive2  ((t :inherit powerline-inactive0)))
   
   '(mode-line-highlight ((t :inherit est-strong)))
   '(mode-line-emphasis  ((t :inherit bold))) ; 
   '(mode-line-buffer-id ((t :inherit emph)))
   ;; '(mode-line-buffer-id-inactive)

   '(spaceline-highlight-face ((t :inherit est-highlight-1)))
   '(spaceline-flycheck-error ((t :inherit est-critical)))
   '(spaceline-flycheck-warning ((t :inherit warning)))
   '(spaceline-flycheck-info ((t :inherit est-emph)))

   '(selectrum-primary-highlight ((t :inherit match)))

   '(sh-quoted-exec ((t :inherit salient)))

   '(smerge-lower   ((t :inherit diff-added)))
   '(smerge-upper   ((t :ihnerit diff-removed)))
   '(smerge-markers ((t inherit shadow)))
   '(smerge-base            ((t :inherit ediff-even-diff-face-Ancestor)))
   '(smerge-refined-added   ((t :inherit ediff-fine-diff-face-A)))
   '(smerge-refined-removed ((t :inherit ediff-fine-diff-face-B)))
   '(smerge-refined-change  ((t :inherit ediff-fine-diff-face-C)))
   
   '(swiper-match-face-1 ((t :inherit match)))
   '(swiper-match-face-2 ((t :inherit match)))
   '(swiper-match-face-3 ((t :inherit match)))
   '(swiper-match-face-4 ((t :inherit match)))

   '(widget-field ((t :inherit (est-faded est-subtle)))))

(enable-theme 'est-style)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Quick palette re-theming

(defun est-lunarized-dark () ;; solarized inspire theme
  (setq est-color-fg-default  "#839496"
        est-color-fg-salient  "#268bd2"
        est-color-fg-popout   "#eee8d5"
        est-color-bg-default   "#002b36"
        est-color-bg-subtle    "#06303c"
        est-color-bg-selected  "#073642")
    (est-reevaluate))


(defun est-lunarized-light () ;; solarized inspired theme
  (interactive)
  (setq est-color-fg-default  "#657b83"
        est-color-fg-salient  "#268bd2"
        est-color-fg-popout   "#d33682"
        est-color-bg-default   "#fdf6e3"
        est-color-bg-subtle    "#fff9d2"
        est-color-bg-selected  "#ffffff")
    (est-reevaluate))

(defun est-cloudy-day () ;; light grey/white palette, blue tones
  (interactive)
  (setq est-color-fg-default     "#3e4759"
        est-color-bg-default     "#ffffff"
        est-color-bg-subtle      "#eef1f6"
        est-color-bg-selected    "#e5e9f0"
        est-color-fg-salient     "#1756c2"
        est-color-fg-popout      "#00e0ff")
    (est-reevaluate))

(defun est-cloudy-night () ;; dark grey palette, blue accents
  (interactive)
  (setq est-color-bg-selected "#192435"
        est-color-bg-subtle   "#242e41"
        est-color-bg-default  "#2b3547"
        est-color-fg-default  "#cccfd4"
        est-color-fg-salient  "#5a8bff"
        est-color-fg-popout   "#00c8ff")
  (est-reevaluate))

(defun est-starry-night-palette () ;; a masterpiece
  (interactive)
  (setq est-color-bg-selected "#00128d"
        est-color-bg-subtle   "#000010"
        est-color-bg-default  "#000050"
        est-color-fg-default  "#819ce6"
        est-color-fg-salient  "#74a5b3"
        est-color-fg-popout   "#e7d97b")
  (est-reevaluate))

(defun est-wood-palette ()
  (interactive)
  (setq est-color-bg-selected "#896a3f"
        est-color-bg-subtle   "#5e454b"
        est-color-bg-default  "#4a3339"
        est-color-fg-default  "#f3f0d7"
        est-color-fg-salient  "#3fab9b"
        est-color-fg-popout   "#26f66a"
        est-accent-chroma 35)
  (est-reevaluate))

(defun est-seaside-palette ()
  (interactive)
  (setq est-color-bg-selected "#004b50"
        est-color-bg-subtle   "#3b4b60"
        est-color-bg-default  "#2c3c51"
        est-color-fg-default  "#c6cdda"
        est-color-fg-salient  "#a77b3f"
        est-color-fg-popout   "#00bbff")
  (est-reevaluate))

(defun est-plan9 () ;; plan9 inspired theme
  (interactive)
  (setq est-color-fg-default     "#424242"
        est-color-bg-default     "#FFFFE8"
        est-color-bg-subtle      "#E5E5D0"
        est-color-bg-selected    "#e8fce8"  ;; green-light
        est-color-fg-salient     "#4fa8a8"  ;; cyan
        est-color-fg-popout      "#b85c57"  ;; purple
	) 
  (custom-set-faces
   '(font-lock-comment-face	((t :inherit est-faded :slant italic)))
   '(org-agenda-structure       ((t :inherit est-default)))
   '(org-agenda-date-weekend    ((t :inherit est-default :slant italic)))
   '(org-agenda-date-today      ((t :inherit est-default :weight bold)))
   '(org-inlinetask       ((t :inherit est-salient)))
   '(org-agenda-date-today ((t :inherit est-default :weight bold)))
   '(org-upcoming-distant-deadline ((t (:inherit est-salient))))
   '(flyspell-duplicate ((t (:underline "DarkOrange"))))
   '(flyspell-incorrect ((t (:underline "Red1"))))
   '(mu4e-header-highlight-face ((t (:inherit est-subtle :extend t))))
   '(mu4e-related-face ((t (:inherit est-faded))))
   )
  (est-reevaluate))

(defun est-gruvbox-light () ;; gruvbox theme
  (interactive)
  (setq est-color-fg-default     "#3c3836"
        est-color-bg-default     "#fbf1c7"
        est-color-bg-subtle      "#ebdbb2"
        est-color-bg-selected    "#d5c4a1"
        est-color-fg-salient     "#9b0006"
        est-color-fg-popout      "#076678")
  (custom-set-faces
   '(font-lock-comment-face	((t :inherit est-faded :slant italic)))
   '(org-agenda-structure       ((t :inherit est-default)))
   '(org-agenda-date-weekend    ((t :inherit est-default :slant italic)))
   '(org-agenda-date-today      ((t :inherit est-default :weight bold)))
   '(org-inlinetask       ((t :inherit est-salient)))
   '(org-agenda-date-today ((t :inherit est-default :weight bold)))
   '(org-upcoming-distant-deadline ((t (:inherit est-salient))))
   '(flyspell-duplicate ((t (:underline "DarkOrange"))))
   '(flyspell-incorrect ((t (:underline "Red1")))))
  (est-reevaluate))

(defun est-gruvbox-dark () ;; gruvbox theme
  (interactive)
  (setq est-color-fg-default     "#ebdbb2"
        est-color-bg-default     "#282828"
        est-color-bg-subtle      "#3c3836"
        est-color-bg-selected    "#504945"
        est-color-fg-salient     "#98971a" ;; green-2
        est-color-fg-popout      "#cc241d" ;; red-1
        )
  (custom-set-faces
   '(font-lock-comment-face	((t :inherit est-faded :slant italic)))
   '(org-agenda-structure       ((t :inherit est-default)))
   '(org-agenda-date-weekend    ((t :inherit est-default :slant italic)))
   '(org-agenda-date-today      ((t :inherit est-default :weight bold)))
   '(org-inlinetask       ((t :inherit est-salient)))
   '(org-agenda-date-today ((t :inherit est-default :weight bold)))
   '(org-upcoming-distant-deadline ((t (:inherit est-salient))))
   '(flyspell-duplicate ((t (:underline "DarkOrange"))))
   '(flyspell-incorrect ((t (:underline "Red1")))))
  (est-reevaluate))


(provide 'est)

;;; est.el ends here
