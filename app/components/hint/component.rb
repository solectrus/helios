module Hint
  # A hint that opens on hover, on tap and on keyboard focus.
  #
  # daisyUI's `.tooltip` has no trigger of its own: it is a pseudo element on a
  # wrapper, opened by `:hover` or by a `:focus-visible` somewhere inside. A
  # hint that hangs on something static - a status dot, a timestamp, a reading -
  # therefore never opens without a pointer. `.dropdown` opens on
  # `:focus-within` and carries a real focusable trigger, which a mouse, a
  # finger and the Tab key all reach, so every such hint is built from one here.
  #
  # Use it where the words are the whole point and nobody can guess them from
  # the screen: the reason a control refuses, the age of a reading, or a
  # paragraph of guidance.
  #
  # `.tooltip` stays where the words label something the screen already carries
  # - an icon-only control, a warning sign, a number that is named beside it.
  # There the bubble is a convenience for the pointer, an `aria-label` or an
  # `sr-only` element carries the same words for everyone else, and the hint is
  # not worth a tab stop.
  class Component < ViewComponent::Base
    # The colours daisyUI gives `tooltip-*`, so a hint that used to be a
    # tooltip keeps its colour.
    VARIANTS = {
      neutral: 'bg-neutral text-neutral-content',
      info: 'bg-info text-info-content',
      success: 'bg-success text-success-content',
      warning: 'bg-warning text-warning-content',
      error: 'bg-error text-error-content',
    }.freeze

    # The measurements daisyUI gives a tooltip bubble, so the two look alike
    # while both exist. The bubble sets its own font: it often hangs on a
    # monospaced or uppercased element, and the words are prose.
    CONTENT_CLASS = 'dropdown-content rounded-field w-max max-w-80 px-2 py-1 text-center ' \
                    'font-sans text-sm leading-tight font-normal normal-case shadow'.freeze

    # text:      the hint. A plain string, or markup for a hint that needs it
    #            (a list, a bilingual label, a value a controller paints). A
    #            long hint wraps its own element and sets the width and the
    #            alignment there, which the bubble then inherits.
    # wrapper_class:
    #            the side the bubble opens to, plus whatever layout classes
    #            the hint needs: the wrapper takes the place of the element it
    #            replaces, so a grid or a join expects to find them there.
    # refused:   the trigger is a control that refuses its action. It says so
    #            but stays focusable - a disabled button takes neither focus
    #            nor tap, so the reason could not reach anyone without a
    #            pointer. The look comes from the btn-disabled the caller puts
    #            in the trigger.
    def initialize(text:, wrapper_class: 'dropdown-top', variant: :neutral, refused: false, trigger_class: nil)
      super()
      @text = text
      @wrapper_class = wrapper_class
      @variant = variant
      @refused = refused
      @trigger_class = trigger_class
    end

    private

    attr_reader :text, :refused, :trigger_class

    # dropdown-hover keeps the pointer behaving as it did. The tap and the Tab
    # key go through :focus-within, which daisyUI gives every dropdown.
    # dropdown-center is not the caller's to choose: the tail sits in the
    # middle of the bubble edge, so the bubble has to be centred on what it
    # points at. `hint` is what the stylesheet beside this file hangs on.
    def wrapper_class
      ['hint dropdown dropdown-hover dropdown-center', @wrapper_class].compact.join(' ')
    end

    def content_class
      "#{CONTENT_CLASS} #{VARIANTS.fetch(@variant)}"
    end
  end
end
