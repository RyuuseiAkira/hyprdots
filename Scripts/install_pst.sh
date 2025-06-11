#!/usr/bin/env bash
#|---/ /+--------------------------------------+---/ /|#
#|--/ /-| Script to apply post install configs |--/ /|#
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

# ---

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
                udev_rules_file_mdrop="/etc/udev/rules.d/99-mdrop.rules"
                udev_rule_mdrop='SUBSYSTEM=="usb", ATTRS{idVendor}=="2fc6", MODE="0666"'

                if grep -q "${udev_rule_mdrop}" "${udev_rules_file_mdrop}" 2>/dev/null; then
                    echo -e "${YELLOW}[WARN]${NC} udev rule already exists for mdrop."
                else
                    echo "${udev_rule_mdrop}" | sudo tee "${udev_rules_file_mdrop}" > /dev/null
                    echo -e "${GREEN}[INFO]${NC} udev rule added to ${udev_rules_file_mdrop}."
                fi
                # Udev reload is done once after all relevant rules are set
            else
                echo -e "${RED}[ERROR]${NC} Failed to move mdrop binary to /usr/local/bin/."
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to build mdrop. Check cargo output for details."
        fi
    else
        echo -e "${RED}[ERROR]${NC} Failed to clone mdrop repository."
    fi
fi # End of cargo check block for mdrop

# ---

## Install msi-ec (Kernel Module)

echo -e "${GREEN}[INFO]${NC} Installing msi-ec (kernel module)..."
msi_ec_dir="${scrDir}/msi-ec" # Define a directory for cloning msi-ec

# Install prerequisites for kernel modules on Arch
echo -e "${GREEN}[INFO]${NC} Installing prerequisites for msi-ec (base-devel, linux-headers)..."
sudo pacman -S --noconfirm --needed base-devel linux-headers
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Failed to install msi-ec build prerequisites. Skipping msi-ec installation."
else
    # Check if dkms is installed, install if not
    if ! pkg_installed dkms; then
        echo -e "${YELLOW}[WARN]${NC} dkms is not installed. Attempting to install dkms with yay..."
        if pkg_installed yay; then
            yay -S --noconfirm dkms
            if [ $? -ne 0 ]; then
                echo -e "${RED}[ERROR]${NC} Failed to install dkms with yay. Skipping msi-ec installation."
                dkms_installed=false
            else
                echo -e "${GREEN}[INFO]${NC} dkms installed successfully."
                dkms_installed=true
            fi
        else
            echo -e "${RED}[ERROR]${NC} yay is not installed. Cannot automatically install dkms. Skipping msi-ec installation."
            dkms_installed=false
        fi
    else
        echo -e "${GREEN}[INFO]${NC} dkms detected."
        dkms_installed=true
    fi

    if [ "$dkms_installed" = true ]; then
        if [ -d "${msi_ec_dir}" ]; then
            echo -e "${YELLOW}[WARN]${NC} msi-ec directory already exists, pulling latest changes..."
            git -C "${msi_ec_dir}" pull
        else
            echo -e "${GREEN}[INFO]${NC} Cloning msi-ec repository..."
            git clone https://github.com/BeardOverflow/msi-ec.git "${msi_ec_dir}"
        fi

        if [ -d "${msi_ec_dir}" ]; then
            echo -e "${GREEN}[INFO]${NC} Building and installing msi-ec kernel module using DKMS..."
            (cd "${msi_ec_dir}" && sudo make dkms-install)

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[INFO]${NC} msi-ec kernel module installed successfully via DKMS."
            else
                echo -e "${RED}[ERROR]${NC} Failed to install msi-ec kernel module via DKMS. Check make output for details."
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to clone msi-ec repository."
        fi
    fi
fi # End of msi-ec installation attempts

# ---
echo -e "${GREEN}[INFO]${NC} Reloading udev rules (for mdrop and other system changes)..."
sudo udevadm control --reload-rules
echo -e "${GREEN}[INFO]${NC} All relevant udev rules applied and reloaded."

# ---

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

# ---

## Dolphin File Manager

# dolphin
if pkg_installed dolphin && pkg_installed xdg-utils; then

    echo -e "${GREEN}[INFO]${NC} [FILEMANAGER] detected // dolphin"
    xdg-mime default org.kde.dolphin.desktop inode/directory
    echo -e "${GREEN}[INFO]${NC} [FILEMANAGER] Setting `xdg-mime query default "inode/directory"` as default file explorer."

else
    echo -e "${YELLOW}[WARN]${NC} dolphin is not installed."
fi

# ---

## Shell Configuration

# shell
"${scrDir}/restore_shl.sh"

# ---

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
