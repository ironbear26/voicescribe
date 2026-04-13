"""
Setup-Skript für VoiceScribe.
Kann mit 'pip install -e .' installiert werden.
"""

from setuptools import setup, find_packages

setup(
    name="VoiceScribe",
    version="1.0.0",
    description="macOS Menu Bar Sprachtranskriptions-App mit Whisper und Claude AI",
    author="VoiceScribe",
    python_requires=">=3.10",
    packages=find_packages(),
    install_requires=[
        "rumps>=0.4.0",
        "sounddevice>=0.4.6",
        "numpy>=1.24.0",
        "faster-whisper>=1.0.0",
        "anthropic>=0.30.0",
        "pynput>=1.7.6",
        "pyperclip>=1.8.2",
        "pyautogui>=0.9.54",
        "scipy>=1.11.0",
    ],
    entry_points={
        "console_scripts": [
            "voicescribe=main:main",
        ],
    },
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: MacOS",
        "License :: OSI Approved :: MIT License",
    ],
)
