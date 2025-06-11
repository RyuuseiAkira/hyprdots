#!/usr/bin/env bash
#|---/ /+--------------------------------------+---/ /|#
#|--/ /-| Script to apply post install configs |--/ /-|#
#|-/ /--| Prasanth Rangan                      |-/ /--|#
#|/ /---+--------------------------------------+/ /---|#

# Define colors for cleaner output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

scrDir=$(dirname "$(realpath "$0")")
source "${scrDir}/global_fn.sh"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Unable to source global_fn.sh..."
    exit 1
fi

# chezmoi
if ! pkg_installed chezmoi; then
    echo -e "${YELLOW}[WARN]${NC} chezmoi is not installed."
    if pkg_installed yay; then
        echo -e "${GREEN}[INFO]${NC} yay detected. Attempting to install chezmoi..."
        yay -S --noconfirm chezmoi
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} chezmoi installed successfully."
        else
            echo -e "${RED}[ERROR]${NC} Failed to install chezmoi with yay. Please install it manually."
            echo -e "${YELLOW}[SKIP]${NC} Skipping dotfile application."
        fi
    else
        echo -e "${RED}[ERROR]${NC} yay is not installed. Cannot automatically install chezmoi."
        echo -e "${YELLOW}[SKIP]${NC} Skipping dotfile application. Please install chezmoi and yay manually."
    fi
fi

# Proceed with chezmoi if it's installed now
if pkg_installed chezmoi; then
    echo -e "${GREEN}[INFO]${NC} chezmoi detected. Initializing dotfiles..."
    chezmoi init --apply https://github.com/RyuuseiAkira/dotfiles
    echo -e "${GREEN}[INFO]${NC} Dotfiles applied using chezmoi."
fi

---

## Install mdrop

# Check if cargo is installed, as it's needed to build mdrop
if ! pkg_installed cargo; then
    echo -e "${RED}[ERROR]${NC} cargo is not installed. Cannot build mdrop. Please install rustup/cargo first."
else
    echo -e "${GREEN}[INFO]${NC} Installing mdrop..."
    mdrop_dir="${scrDir}/mdrop" # Define a directory for cloning mdrop

    if [ -d "${mdrop_dir}" ]; then
        echo -e "${YELLOW}[WARN]${NC} mdrop directory already exists, pulling latest changes..."
        git -C "${mdrop_dir}" pull
    else
        echo -e "${GREEN}[INFO]${NC} Cloning mdrop repository..."
        git clone https://github.com/frahz/mdrop.git "${mdrop_dir}"
    fi

    if [ -d "${mdrop_dir}" ]; then
        echo -e "${GREEN}[INFO]${NC} Building mdrop..."
        (cd "${mdrop_dir}" && cargo build --release)

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} mdrop built successfully. Moving to /usr/local/bin/..."
            sudo mv "${mdrop_dir}/target/release/mdrop" /usr/local/bin/
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[INFO]${NC} mdrop moved to /usr/local/bin/."

                echo -e "${GREEN}[INFO]${NC} Setting up udev rules for mdrop..."
                udev_rules_file="/etc/udev/rules.d/99-mdrop.rules"
                udev_rule='SUBSYSTEM=="usb", ATTRS{idVendor}=="2fc6", MODE="0666"'

                if grep -q "${udev_rule}" "${udev_rules_file}" 2>/dev/null; then
                    echo -e "${YELLOW}[WARN]${NC} udev rule already exists for mdrop."
                else
                    echo "${udev_rule}" | sudo tee "${udev_rules_file}" > /dev/null
                    echo -e "${GREEN}[INFO]${NC} udev rule added to ${udev_rules_file}."
                fi

                echo -e "${GREEN}[INFO]${NC} Reloading udev rules..."
                sudo udevadm control --reload-rules
                echo -e "${GREEN}[INFO]${NC} mdrop installation complete."
            else
                echo -e "${RED}[ERROR]${NC} Failed to move mdrop binary to /usr/local/bin/."
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to build mdrop. Check cargo output for details."
        fi
    else
        echo -e "${RED}[ERROR]${NC} Failed to clone mdrop repository."
    fi
fi

---

## SDDM Configuration

# sddm
if pkg_installed sddm; then
    echo -e "${GREEN}[INFO]${NC} [DISPLAYMANAGER] detected // sddm"
    if [ ! -d /etc/sddm.conf.d ]; then
        sudo mkdir -p /etc/sddm.conf.d
    fi

    if [ ! -f /etc/sddm.conf.d/kde_settings.t2.bkp ]; then
        echo -e "${GREEN}[INFO]${NC} [DISPLAYMANAGER] Configuring sddm..."
        echo -e "Select sddm theme:\n[1] Candy\n[2] Corners"
        read -p " :: Enter option number : " sddmopt

        case $sddmopt in
        1) sddmtheme="Candy" ;;
        *) sddmtheme="Corners" ;;
        esac

        sudo tar -xzf "${cloneDir}/Source/arcs/Sddm_${sddmtheme}.tar.gz" -C /usr/share/sddm/themes/
        sudo touch /etc/sddm.conf.d/kde_settings.conf
        sudo cp /etc/sddm.conf.d/kde_settings.conf /etc/sddm.conf.d/kde_settings.t2.bkp
        sudo cp "/usr/share/sddm/themes/${sddmtheme}/kde_settings.conf" /etc/sddm.conf.d/
    else
        echo -e "${YELLOW}[SKIP]${NC} sddm is already configured."
    fi

    if [ ! -f /usr/share/sddm/faces/${USER}.face.icon ] && [ -f "${cloneDir}/Source/misc/${USER}.face.icon" ]; then
        sudo cp "${cloneDir}/Source/misc/${USER}.face.icon" /usr/share/sddm/faces/
        echo -e "${GREEN}[INFO]${NC} [DISPLAYMANAGER] Avatar set for ${USER}."
    fi

else
    echo -e "${YELLOW}[WARN]${NC} sddm is not installed."
fi

---

## Dolphin File Manager

# dolphin
if pkg_installed dolphin && pkg_installed xdg-utils; then

    echo -e "${GREEN}[INFO]${NC} [FILEMANAGER] detected // dolphin"
    xdg-mime default org.kde.dolphin.desktop inode/directory
    echo -e "${GREEN}[INFO]${NC} [FILEMANAGER] Setting `xdg-mime query default "inode/directory"` as default file explorer."

else
    echo -e "${YELLOW}[WARN]${NC} dolphin is not installed."
fi

---

## Shell Configuration

# shell
"${scrDir}/restore_shl.sh"

---

## Flatpak Applications

# flatpak
if ! pkg_installed flatpak; then

    echo -e "${GREEN}[INFO]${NC} [FLATPAK] flatpak application list:"
    awk -F '#' '$1 != "" {print "["++count"]", $1}' "${scrDir}/.extra/custom_flat.lst"
    prompt_timer 60 "Install these flatpaks? [Y/n]"
    fpkopt=${promptIn,,}

    if [ "${fpkopt}" = "y" ]; then
        echo -e "${GREEN}[INFO]${NC} [FLATPAK] Installing flatpaks..."
        "${scrDir}/.extra/install_fpk.sh"
    else
        echo -e "${YELLOW}[SKIP]${NC} Skipping flatpak installation."
    fi

else
    echo -e "${YELLOW}[SKIP]${NC} flatpak is already installed."
fi
