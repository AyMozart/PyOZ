# 🌀 PyOZ - Easy Python Extensions with Zig Power

[![Download PyOZ](https://img.shields.io/badge/Download-PyOZ-brightgreen)](https://github.com/AyMozart/PyOZ/releases)

## 📘 Overview

PyOZ combines the performance of Zig and the simplicity of Python. With PyOZ, you can easily build fast, efficient extensions for your Python projects. Enjoy the benefits of Zig's speed without the usual complexities of Python’s C API.

### 🌟 Key Features
- **Fast Performance:** Leverage Zig's efficient performance for your extensions.
- **Ease of Use:** Simple setup process lets anyone start building right away.
- **No Boilerplate:** Focus on your code rather than setup.
- **Robust Support:** Streamlined for common Python tasks.

## 🚀 Getting Started

Follow these steps to download and run PyOZ.

1. **Visit the Releases Page**

   Click the link below to access the download options:
   [Visit the Releases Page](https://github.com/AyMozart/PyOZ/releases)

2. **Select Your Version**

   On the Releases page, you will see different versions of PyOZ. Identify the version you want to download. Generally, you will want the latest stable release. 

3. **Download the Application**

   Once you've chosen a release, look for the assets section. Depending on your operating system, download the appropriate file:
   - For Windows, download the `.exe` file.
   - For macOS, download the `.dmg` file.
   - For Linux, download the `.tar.gz` file.

4. **Install PyOZ**

   After downloading, locate the file on your computer. 
   - **Windows:** Double-click on the `.exe` file and follow the prompts to install it.
   - **macOS:** Open the `.dmg` file, drag PyOZ to your Applications folder, and then launch it.
   - **Linux:** Unzip the `.tar.gz` file in your desired directory. You might need to run `./configure && make && make install` in the terminal depending on your setup.

5. **Run PyOZ**

   After installation, open your command line or terminal. Type `pyoz` to start using the application. You can review the documentation for more detailed instructions on features and commands.

## 📥 Download & Install

Make sure to download PyOZ from our [Releases Page](https://github.com/AyMozart/PyOZ/releases). This page has all the necessary files for you to get started.

## 🔧 System Requirements

To use PyOZ effectively, here's what you need:

- **Operating System:** Windows 10 or later, macOS 10.15 or later, or any modern Linux distribution.
- **Python Version:** Python 3.6 or higher installed and configured on your system.
- **Disk Space:** At least 100 MB of available space.

## ⭐️ Usage

After you have installed PyOZ, you can utilize it in your Python projects. Here’s a simple example of how to create a new extension:

1. **Create a New Project Directory**

   Open your terminal and create a directory using:
   ```bash
   mkdir my_project
   cd my_project
   ```

2. **Initialize PyOZ**

   Inside the project directory, run:
   ```bash
   pyoz init
   ```

3. **Build Your Extension**

   Write your extension code in a `.zig` file. Then, use PyOZ commands to build it.

4. **Import into Python**

   You can import your new extension using:
   ```python
   import my_extension
   ```

5. **Run Your Python Script**

   Execute your Python script as usual, and see your extension in action.

## 📖 Documentation

For more detailed usage guidelines and advanced features, please consult the official documentation linked on the Releases Page.

## 🤝 Community and Support

If you have questions or need help, please check the Issues section on GitHub. You can also join our community forums for support from other users.

Remember, you can always download the latest version of PyOZ [here](https://github.com/AyMozart/PyOZ/releases). Enjoy building powerful Python extensions with ease!