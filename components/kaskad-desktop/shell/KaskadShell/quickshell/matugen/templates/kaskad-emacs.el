;;; kaskad-emacs-theme.el --- Enhanced theme using Matugen SCSS variables with kaskad16 colors -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Generated (Enhanced)
;; Version: 1.3
;; Package-Requires: ((emacs "24.1"))
;; Keywords: faces

;;; Commentary:

;; An enhanced theme using Matugen SCSS variables integrated with kaskad16 colors:
;; - Rich color palette from kaskad16 for vibrant syntax highlighting
;; - Improved contrast and readability
;; - Better source block distinction with refined backgrounds
;; - Enhanced org-mode styling with hidden asterisks
;; - Superior visual hierarchy and modern aesthetics

;;; Code:

(deftheme kaskad-emacs "Enhanced theme using Matugen variables with kaskad16 color integration.")

;; Define all the color variables (replaced by template processor)
(let* ((bg "{{colors.background.default.hex}}")
      (err "{{kaskad16.color1.default.hex}}")  ; Red from kaskad16
      (err-container "{{colors.error_container.default.hex}}")
      (on-background "{{colors.on_background.default.hex}}")
      (on-err "{{colors.on_error.default.hex}}")
      (on-err-container "{{colors.on_error_container.default.hex}}")
      (on-primary "{{colors.on_primary.default.hex}}")
      (on-primary-container "{{colors.on_primary_container.default.hex}}")
      (on-secondary "{{colors.on_secondary.default.hex}}")
      (on-secondary-container "{{colors.on_secondary_container.default.hex}}")
      (on-surface "{{colors.on_surface.default.hex}}")
      (on-surface-variant "{{colors.on_surface_variant.default.hex}}")
      (on-tertiary "{{colors.on_tertiary.default.hex}}")
      (on-tertiary-container "{{colors.on_tertiary_container.default.hex}}")
      (outline-color "{{colors.outline.default.hex}}")
      (outline-variant "{{colors.outline_variant.default.hex}}")
      (primary "{{colors.primary.default.hex}}")
      (primary-container "{{colors.primary_container.default.hex}}")
      (secondary "{{colors.secondary.default.hex}}")
      (secondary-container "{{colors.secondary_container.default.hex}}")
      (shadow "{{colors.shadow.default.hex}}")
      (surface "{{colors.surface.default.hex}}")
      (surface-container "{{colors.surface_container_high.default.hex}}")
      (surface-container-high "{{colors.surface_container_highest.default.hex}}")
      (surface-container-highest "{{colors.surface_container_high.default.hex}}")
      (surface-container-low "{{colors.surface_container_low.default.hex}}")
      (surface-container-lowest "{{colors.surface_container_lowest.default.hex}}")
      (surface-variant "{{colors.surface_variant.default.hex}}")
      (tertiary "{{colors.tertiary.default.hex}}")
      (tertiary-container "{{colors.tertiary_container.default.hex}}")

      ;; Enhanced kaskad16 colors for better syntax highlighting
      (kaskad-red "{{kaskad16.color1.default.hex}}")          ; Bright red
      (kaskad-red-alt "{{kaskad16.color9.default.hex}}")      ; Alternative red
      (kaskad-green "{{kaskad16.color2.default.hex}}")        ; Vibrant green
      (kaskad-green-bright "{{kaskad16.color10.default.hex}}") ; Bright green
      (kaskad-yellow "{{kaskad16.color3.default.hex}}")       ; Warm yellow
      (kaskad-yellow-bright "{{kaskad16.color11.default.hex}}") ; Bright yellow
      (kaskad-blue "{{kaskad16.color4.default.hex}}")         ; Blue-green
      (kaskad-magenta "{{kaskad16.color5.default.hex}}")      ; Teal-magenta
      (kaskad-cyan "{{kaskad16.color6.default.hex}}")         ; Bright cyan
      (kaskad-cyan-bright "{{kaskad16.color12.default.hex}}") ; Brightest cyan
      (kaskad-cyan-dark "{{kaskad16.color13.default.hex}}")   ; Dark cyan
      (kaskad-teal "{{kaskad16.color14.default.hex}}")        ; Dark teal
      (kaskad-fg "{{kaskad16.color7.default.hex}}")           ; Light foreground
      (kaskad-gray "{{kaskad16.color8.default.hex}}")         ; Gray
      (kaskad-white "{{kaskad16.color15.default.hex}}")       ; White

      ;; Map success colors to green
      (success "{{kaskad16.color2.default.hex}}")
      (on-success "{{colors.on_tertiary.default.hex}}")
      (success-container "{{colors.tertiary_container.default.hex}}")
      (on-success-container "{{colors.on_tertiary_container.default.hex}}")

      ;; Map fixed colors
      (primary-fixed "{{colors.primary_fixed.default.hex}}")
      (primary-fixed-dim "{{colors.primary_fixed_dim.default.hex}}")
      (secondary-fixed "{{colors.secondary_fixed.default.hex}}")
      (secondary-fixed-dim "{{colors.secondary_fixed_dim.default.hex}}")
      (tertiary-fixed "{{colors.tertiary_fixed.default.hex}}")
      (tertiary-fixed-dim "{{colors.tertiary_fixed_dim.default.hex}}")
      (on-primary-fixed "{{colors.on_primary_fixed.default.hex}}")
      (on-primary-fixed-variant "{{colors.on_primary_fixed_variant.default.hex}}")
      (on-secondary-fixed "{{colors.on_secondary_fixed.default.hex}}")
      (on-secondary-fixed-variant "{{colors.on_secondary_fixed_variant.default.hex}}")
      (on-tertiary-fixed "{{colors.on_tertiary_fixed.default.hex}}")
      (on-tertiary-fixed-variant "{{colors.on_tertiary_fixed_variant.default.hex}}")

      ;; Map inverse colors
      (inverse-on-surface "{{colors.inverse_on_surface.default.hex}}")
      (inverse-primary "{{colors.inverse_primary.default.hex}}")
      (inverse-surface "{{colors.inverse_surface.default.hex}}")

      ;; Terminal colors from kaskad16
      (term0 "{{kaskad16.color0.default.hex}}")
      (term1 "{{kaskad16.color1.default.hex}}")
      (term2 "{{kaskad16.color2.default.hex}}")
      (term3 "{{kaskad16.color3.default.hex}}")
      (term4 "{{kaskad16.color4.default.hex}}")
      (term5 "{{kaskad16.color5.default.hex}}")
      (term6 "{{kaskad16.color6.default.hex}}")
      (term7 "{{kaskad16.color7.default.hex}}")
      (term8 "{{kaskad16.color8.default.hex}}")
      (term9 "{{kaskad16.color9.default.hex}}")
      (term10 "{{kaskad16.color10.default.hex}}")
      (term11 "{{kaskad16.color11.default.hex}}")
      (term12 "{{kaskad16.color12.default.hex}}")
      (term13 "{{kaskad16.color13.default.hex}}")
      (term14 "{{kaskad16.color14.default.hex}}")
      (term15 "{{kaskad16.color15.default.hex}}"))

  (custom-theme-set-faces
   'kaskad-emacs
   ;; Basic faces
   `(default ((t (:background ,bg :foreground ,on-background))))
   `(cursor ((t (:background ,kaskad-cyan-bright))))
   `(highlight ((t (:background ,primary-container :foreground ,on-primary-container))))
   `(region ((t (:background ,primary-container :foreground ,kaskad-cyan-bright :extend t))))
   `(secondary-selection ((t (:background ,secondary-container :foreground ,on-secondary-container :extend t))))
   `(isearch ((t (:background ,kaskad-yellow :foreground ,bg :weight bold))))
   `(lazy-highlight ((t (:background ,secondary-container :foreground ,kaskad-yellow-bright))))
   `(vertical-border ((t (:foreground ,surface-variant))))
   `(border ((t (:background ,surface-variant :foreground ,surface-variant))))
   `(fringe ((t (:background ,surface :foreground ,kaskad-gray))))
   `(shadow ((t (:foreground ,kaskad-gray))))
   `(link ((t (:foreground ,kaskad-cyan-bright :underline t))))
   `(link-visited ((t (:foreground ,kaskad-magenta :underline t))))
   `(success ((t (:foreground ,success))))
   `(warning ((t (:foreground ,kaskad-yellow))))
   `(error ((t (:foreground ,err))))
   `(match ((t (:background ,kaskad-yellow :foreground ,bg :weight bold))))

   ;; Font-lock - enhanced with kaskad16 colors for vibrant syntax highlighting
   `(font-lock-builtin-face ((t (:foreground ,kaskad-cyan-bright))))
   `(font-lock-comment-face ((t (:foreground ,kaskad-gray :slant italic))))
   `(font-lock-comment-delimiter-face ((t (:foreground ,outline-variant))))
   `(font-lock-constant-face ((t (:foreground ,kaskad-yellow-bright :weight bold))))
   `(font-lock-doc-face ((t (:foreground ,kaskad-fg :slant italic))))
   `(font-lock-function-name-face ((t (:foreground ,kaskad-cyan :weight bold))))
   `(font-lock-keyword-face ((t (:foreground ,kaskad-red-alt :weight bold))))
   `(font-lock-string-face ((t (:foreground ,kaskad-green))))
   `(font-lock-type-face ((t (:foreground ,kaskad-yellow))))
   `(font-lock-variable-name-face ((t (:foreground ,kaskad-fg))))
   `(font-lock-warning-face ((t (:foreground ,err :weight bold))))
   `(font-lock-preprocessor-face ((t (:foreground ,kaskad-teal))))
   `(font-lock-negation-char-face ((t (:foreground ,kaskad-red))))

   ;; Show paren
   `(show-paren-match ((t (:background ,primary-container :foreground ,kaskad-cyan-bright :weight bold))))
   `(show-paren-mismatch ((t (:background ,err-container :foreground ,on-err-container :weight bold))))

   ;; Mode line - improved status bar styling
   `(mode-line ((t (:background ,surface-container :foreground ,on-surface :box nil))))
   `(mode-line-inactive ((t (:background ,surface :foreground ,kaskad-gray :box nil))))
   `(mode-line-buffer-id ((t (:foreground ,kaskad-cyan :weight bold))))
   `(mode-line-emphasis ((t (:foreground ,kaskad-cyan :weight bold))))
   `(mode-line-highlight ((t (:foreground ,kaskad-cyan-bright :box nil))))

   ;; Improved Source blocks - seamless integration
   `(org-block ((t (:background ,surface-container-low :extend t :inherit fixed-pitch))))
   `(org-block-begin-line ((t (:background ,surface-container-low :foreground ,kaskad-teal :extend t :slant italic :inherit fixed-pitch))))
   `(org-block-end-line ((t (:background ,surface-container-low :foreground ,kaskad-teal :extend t :slant italic :inherit fixed-pitch))))
   `(org-code ((t (:background ,surface-container-low :foreground ,kaskad-yellow-bright :inherit fixed-pitch))))
   `(org-verbatim ((t (:background ,surface-container-low :foreground ,kaskad-cyan :inherit fixed-pitch))))
   `(org-meta-line ((t (:foreground ,kaskad-gray :slant italic))))

   ;; Org mode with enhanced colors and hidden asterisks
   `(org-level-1 ((t (:foreground ,kaskad-cyan :weight bold :height 1.2))))
   `(org-level-2 ((t (:foreground ,kaskad-blue :weight bold :height 1.1))))
   `(org-level-3 ((t (:foreground ,kaskad-magenta :weight bold))))
   `(org-level-4 ((t (:foreground ,kaskad-green :weight bold))))
   `(org-level-5 ((t (:foreground ,kaskad-yellow :weight bold))))
   `(org-level-6 ((t (:foreground ,kaskad-cyan-bright :weight bold))))
   `(org-level-7 ((t (:foreground ,kaskad-red-alt :weight bold))))
   `(org-level-8 ((t (:foreground ,kaskad-teal :weight bold))))
   `(org-document-title ((t (:foreground ,kaskad-cyan :weight bold :height 1.3))))
   `(org-document-info ((t (:foreground ,kaskad-blue))))
   `(org-todo ((t (:foreground ,kaskad-red :weight bold))))
   `(org-done ((t (:foreground ,success :weight bold))))
   `(org-headline-done ((t (:foreground ,kaskad-gray))))
   `(org-hide ((t (:foreground ,bg))))
   `(org-ellipsis ((t (:foreground ,kaskad-blue :underline nil))))
   `(org-table ((t (:foreground ,kaskad-magenta :inherit fixed-pitch))))
   `(org-formula ((t (:foreground ,kaskad-yellow-bright :inherit fixed-pitch))))
   `(org-checkbox ((t (:foreground ,kaskad-cyan :weight bold :inherit fixed-pitch))))
   `(org-date ((t (:foreground ,kaskad-teal :underline t))))
   `(org-special-keyword ((t (:foreground ,kaskad-gray :slant italic))))
   `(org-tag ((t (:foreground ,kaskad-gray :weight normal))))

   ;; Magit with enhanced diff colors
   `(magit-section-highlight ((t (:background ,surface-container-low))))
   `(magit-diff-hunk-heading ((t (:background ,surface-container :foreground ,kaskad-gray))))
   `(magit-diff-hunk-heading-highlight ((t (:background ,surface-container-high :foreground ,on-surface))))
   `(magit-diff-context ((t (:foreground ,kaskad-gray))))
   `(magit-diff-context-highlight ((t (:background ,surface-container-low :foreground ,on-surface))))
   `(magit-diff-added ((t (:background ,success-container :foreground ,kaskad-green-bright))))
   `(magit-diff-added-highlight ((t (:background ,success-container :foreground ,kaskad-green-bright :weight bold))))
   `(magit-diff-removed ((t (:background ,err-container :foreground ,kaskad-red-alt))))
   `(magit-diff-removed-highlight ((t (:background ,err-container :foreground ,kaskad-red-alt :weight bold))))
   `(magit-hash ((t (:foreground ,kaskad-gray))))
   `(magit-branch-local ((t (:foreground ,kaskad-blue :weight bold))))
   `(magit-branch-remote ((t (:foreground ,kaskad-cyan :weight bold))))

   ;; Company
   `(company-tooltip ((t (:background ,surface-container :foreground ,on-surface))))
   `(company-tooltip-selection ((t (:background ,primary-container :foreground ,kaskad-cyan-bright))))
   `(company-tooltip-common ((t (:foreground ,kaskad-cyan))))
   `(company-tooltip-common-selection ((t (:foreground ,kaskad-cyan-bright :weight bold))))
   `(company-tooltip-annotation ((t (:foreground ,kaskad-yellow))))
   `(company-scrollbar-fg ((t (:background ,kaskad-cyan))))
   `(company-scrollbar-bg ((t (:background ,surface-variant))))
   `(company-preview ((t (:foreground ,kaskad-gray :slant italic))))
   `(company-preview-common ((t (:foreground ,kaskad-cyan :slant italic))))

   ;; Ido
   `(ido-first-match ((t (:foreground ,kaskad-cyan :weight bold))))
   `(ido-only-match ((t (:foreground ,kaskad-green :weight bold))))
   `(ido-subdir ((t (:foreground ,kaskad-blue))))
   `(ido-indicator ((t (:foreground ,kaskad-red))))
   `(ido-virtual ((t (:foreground ,kaskad-gray))))

   ;; Helm
   `(helm-selection ((t (:background ,primary-container :foreground ,kaskad-cyan-bright))))
   `(helm-match ((t (:foreground ,kaskad-cyan :weight bold))))
   `(helm-source-header ((t (:background ,surface-container-high :foreground ,kaskad-cyan :weight bold :height 1.1))))
   `(helm-candidate-number ((t (:foreground ,kaskad-yellow :weight bold))))
   `(helm-ff-directory ((t (:foreground ,kaskad-cyan :weight bold))))
   `(helm-ff-file ((t (:foreground ,on-surface))))
   `(helm-ff-executable ((t (:foreground ,kaskad-green))))

   ;; corfu
   `(corfu-default ((t (:background ,surface-container :foreground ,on-surface))))
   `(corfu-current ((t (:background ,primary-container :foreground ,kaskad-cyan-bright))))

   ;; Which-key
   `(which-key-key-face ((t (:foreground ,kaskad-cyan :weight bold))))
   `(which-key-separator-face ((t (:foreground ,outline-variant))))
   `(which-key-command-description-face ((t (:foreground ,on-surface))))
   `(which-key-group-description-face ((t (:foreground ,kaskad-blue))))
   `(which-key-special-key-face ((t (:foreground ,kaskad-yellow :weight bold))))

   ;; Line numbers
   `(line-number ((t (:foreground ,kaskad-gray :inherit default))))
   `(line-number-current-line ((t (:foreground ,kaskad-cyan :weight bold :inherit default))))

   ;; Parenthesis matching
   `(sp-show-pair-match-face ((t (:background ,primary-container :foreground ,kaskad-cyan-bright))))
   `(sp-show-pair-mismatch-face ((t (:background ,err-container :foreground ,on-err-container))))

   ;; Rainbow delimiters - vibrant colors
   `(rainbow-delimiters-depth-1-face ((t (:foreground ,kaskad-cyan))))
   `(rainbow-delimiters-depth-2-face ((t (:foreground ,kaskad-yellow))))
   `(rainbow-delimiters-depth-3-face ((t (:foreground ,kaskad-green))))
   `(rainbow-delimiters-depth-4-face ((t (:foreground ,kaskad-blue))))
   `(rainbow-delimiters-depth-5-face ((t (:foreground ,kaskad-magenta))))
   `(rainbow-delimiters-depth-6-face ((t (:foreground ,kaskad-cyan-bright))))
   `(rainbow-delimiters-depth-7-face ((t (:foreground ,kaskad-yellow-bright))))
   `(rainbow-delimiters-depth-8-face ((t (:foreground ,kaskad-green-bright))))
   `(rainbow-delimiters-depth-9-face ((t (:foreground ,kaskad-red-alt))))
   `(rainbow-delimiters-mismatched-face ((t (:foreground ,err :weight bold))))
   `(rainbow-delimiters-unmatched-face ((t (:foreground ,err :weight bold))))

   ;; Dired
   `(dired-directory ((t (:foreground ,kaskad-cyan :weight bold))))
   `(dired-ignored ((t (:foreground ,kaskad-gray))))
   `(dired-flagged ((t (:foreground ,kaskad-red))))
   `(dired-marked ((t (:foreground ,kaskad-yellow :weight bold))))
   `(dired-symlink ((t (:foreground ,kaskad-magenta :slant italic))))
   `(dired-header ((t (:foreground ,kaskad-cyan :weight bold :height 1.1))))

   ;; Terminal colors
   `(term-color-black ((t (:foreground ,term0 :background ,term0))))
   `(term-color-red ((t (:foreground ,term1 :background ,term1))))
   `(term-color-green ((t (:foreground ,term2 :background ,term2))))
   `(term-color-yellow ((t (:foreground ,term3 :background ,term3))))
   `(term-color-blue ((t (:foreground ,term4 :background ,term4))))
   `(term-color-magenta ((t (:foreground ,term5 :background ,term5))))
   `(term-color-cyan ((t (:foreground ,term6 :background ,term6))))
   `(term-color-white ((t (:foreground ,term7 :background ,term7))))

   ;; EShell
   `(eshell-prompt ((t (:foreground ,kaskad-cyan :weight bold))))
   `(eshell-ls-directory ((t (:foreground ,kaskad-cyan :weight bold))))
   `(eshell-ls-symlink ((t (:foreground ,kaskad-magenta :slant italic))))
   `(eshell-ls-executable ((t (:foreground ,kaskad-green))))
   `(eshell-ls-archive ((t (:foreground ,kaskad-yellow))))
   `(eshell-ls-backup ((t (:foreground ,kaskad-gray))))
   `(eshell-ls-clutter ((t (:foreground ,kaskad-red))))
   `(eshell-ls-missing ((t (:foreground ,kaskad-red))))
   `(eshell-ls-product ((t (:foreground ,on-surface-variant))))
   `(eshell-ls-readonly ((t (:foreground ,kaskad-gray))))
   `(eshell-ls-special ((t (:foreground ,kaskad-blue))))
   `(eshell-ls-unreadable ((t (:foreground ,kaskad-gray))))

   ;; Improved markdown mode
   `(markdown-header-face ((t (:foreground ,kaskad-cyan :weight bold))))
   `(markdown-header-face-1 ((t (:foreground ,kaskad-cyan :weight bold :height 1.2))))
   `(markdown-header-face-2 ((t (:foreground ,kaskad-blue :weight bold :height 1.1))))
   `(markdown-header-face-3 ((t (:foreground ,kaskad-magenta :weight bold))))
   `(markdown-header-face-4 ((t (:foreground ,kaskad-green :weight bold))))
   `(markdown-inline-code-face ((t (:foreground ,kaskad-yellow-bright :background ,surface-container-low :inherit fixed-pitch))))
   `(markdown-code-face ((t (:background ,surface-container-low :extend t :inherit fixed-pitch))))
   `(markdown-pre-face ((t (:background ,surface-container-low :inherit fixed-pitch))))
   `(markdown-table-face ((t (:foreground ,kaskad-magenta :inherit fixed-pitch))))

   ;; Web mode
   `(web-mode-html-tag-face ((t (:foreground ,kaskad-cyan))))
   `(web-mode-html-tag-bracket-face ((t (:foreground ,kaskad-gray))))
   `(web-mode-html-attr-name-face ((t (:foreground ,kaskad-yellow))))
   `(web-mode-html-attr-value-face ((t (:foreground ,kaskad-green))))
   `(web-mode-css-selector-face ((t (:foreground ,kaskad-cyan))))
   `(web-mode-css-property-name-face ((t (:foreground ,kaskad-blue))))
   `(web-mode-css-string-face ((t (:foreground ,kaskad-green))))

   ;; Flycheck
   `(flycheck-error ((t (:underline (:style wave :color ,err)))))
   `(flycheck-warning ((t (:underline (:style wave :color ,kaskad-yellow)))))
   `(flycheck-info ((t (:underline (:style wave :color ,kaskad-blue)))))
   `(flycheck-fringe-error ((t (:foreground ,err))))
   `(flycheck-fringe-warning ((t (:foreground ,kaskad-yellow))))
   `(flycheck-fringe-info ((t (:foreground ,kaskad-blue))))

   ;; Mini-buffer customization
   `(minibuffer-prompt ((t (:foreground ,kaskad-cyan :weight bold))))

   ;; Improved search highlighting
   `(lsp-face-highlight-textual ((t (:background ,primary-container :foreground ,kaskad-cyan-bright :weight bold))))
   `(lsp-face-highlight-read ((t (:background ,secondary-container :foreground ,kaskad-yellow-bright :weight bold))))
   `(lsp-face-highlight-write ((t (:background ,tertiary-container :foreground ,kaskad-green-bright :weight bold))))

   ;; Info and help modes
   `(info-title-1 ((t (:foreground ,kaskad-cyan :weight bold :height 1.3))))
   `(info-title-2 ((t (:foreground ,kaskad-blue :weight bold :height 1.2))))
   `(info-title-3 ((t (:foreground ,kaskad-magenta :weight bold :height 1.1))))
   `(info-title-4 ((t (:foreground ,kaskad-green :weight bold))))
   `(Info-quoted ((t (:foreground ,kaskad-yellow))))
   `(info-menu-header ((t (:foreground ,kaskad-cyan :weight bold))))
   `(info-menu-star ((t (:foreground ,kaskad-cyan))))
   `(info-node ((t (:foreground ,kaskad-blue :weight bold))))

   ;; Tabs
   `(tab-bar ((t (:background ,surface-container :foreground ,on-surface :box nil))))
   `(tab-bar-tab ((t (:background ,surface-container-high :foreground ,kaskad-cyan :weight bold :box nil))))
   `(tab-bar-tab-inactive ((t (:background ,surface :foreground ,kaskad-gray :box nil))))

   `(tab-line ((t (:background ,surface-container :foreground ,on-surface :box nil))))
   `(tab-line-tab ((t (:background ,surface :foreground ,kaskad-gray :box nil))))
   `(tab-line-tab-current ((t (:background ,surface-container-high :foreground ,kaskad-cyan :weight bold :box nil))))
   `(tab-line-tab-inactive ((t (:background ,surface :foreground ,kaskad-gray :box nil))))
   `(tab-line-highlight ((t (:background ,surface-container-highest :foreground ,kaskad-cyan-bright))))

   `(centaur-tabs-default ((t (:background ,surface-container :foreground ,on-surface))))
   `(centaur-tabs-selected ((t (:background ,surface-container-high :foreground ,kaskad-cyan :weight bold))))
   `(centaur-tabs-unselected ((t (:background ,surface :foreground ,kaskad-gray))))
   `(centaur-tabs-selected-modified ((t (:background ,surface-container-high :foreground ,kaskad-yellow :weight bold))))
   `(centaur-tabs-unselected-modified ((t (:background ,surface :foreground ,kaskad-yellow))))
   `(centaur-tabs-active-bar-face ((t (:background ,kaskad-cyan))))

   ;; Fixed-pitch faces
   `(fixed-pitch ((t (:family "monospace"))))
   `(fixed-pitch-serif ((t (:family "monospace serif"))))

   ;; Variable-pitch face
   `(variable-pitch ((t (:family "sans serif"))))
   ))

;; Add org-mode hooks for hiding leading stars
(with-eval-after-load 'org
  (setq org-hide-leading-stars t)
  (setq org-startup-indented t))

;;;###autoload
(when load-file-name
  (add-to-list 'custom-theme-load-path
               (file-name-as-directory (file-name-directory load-file-name))))

(provide-theme 'kaskad-emacs)
;;; kaskad-emacs-theme.el ends here
