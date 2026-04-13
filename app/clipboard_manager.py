"""
Zwischenablage-Verwaltung und Auto-Einfügen.
Kopiert Text in die Zwischenablage und simuliert optional Cmd+V.
"""

import logging
import time

logger = logging.getLogger(__name__)


def copy_to_clipboard(text: str):
    """
    Kopiert Text in die macOS-Zwischenablage.

    Args:
        text: Der zu kopierende Text.

    Raises:
        RuntimeError: Wenn pyperclip nicht verfügbar ist oder das Kopieren fehlschlägt.
    """
    if not text:
        logger.warning("Leerer Text – nichts in die Zwischenablage kopiert.")
        return

    try:
        import pyperclip
        pyperclip.copy(text)
        logger.info("Text in Zwischenablage kopiert (%d Zeichen).", len(text))
    except ImportError as e:
        raise RuntimeError(
            "pyperclip ist nicht installiert. Bitte 'pip install pyperclip' ausführen."
        ) from e
    except Exception as e:
        logger.error("Fehler beim Kopieren in die Zwischenablage: %s", e)
        raise RuntimeError(f"Zwischenablage-Fehler: {e}") from e


def auto_paste(delay: float = 0.15):
    """
    Simuliert Cmd+V auf macOS, um den Zwischenablagen-Inhalt einzufügen.
    Wartet kurz, damit die Zwischenablage bereit ist.

    Args:
        delay: Wartezeit in Sekunden vor dem Einfügen (Standard: 150 ms).
    """
    time.sleep(delay)

    try:
        import pyautogui

        # macOS: Cmd+V
        pyautogui.hotkey("command", "v")
        logger.info("Auto-Einfügen ausgeführt (Cmd+V).")
    except ImportError as e:
        raise RuntimeError(
            "pyautogui ist nicht installiert. Bitte 'pip install pyautogui' ausführen."
        ) from e
    except Exception as e:
        logger.error("Fehler beim Auto-Einfügen: %s", e)
        raise RuntimeError(f"Auto-Einfügen fehlgeschlagen: {e}") from e
